using System;
using System.Collections.Concurrent;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;

namespace Jellyfin.Plugin.HomeplayBackup;

/// <summary>
/// Where an upload stands: finished, or how many bytes the server already has.
/// </summary>
/// <param name="Done">The file is complete and in place.</param>
/// <param name="Offset">Bytes already received; the next chunk starts here.</param>
public sealed record UploadState(bool Done, long Offset);

/// <summary>
/// Thrown when a request cannot be accepted, e.g. a chunk that does not start where the
/// previous one ended.
/// </summary>
public sealed class UploadException : Exception
{
    /// <summary>
    /// Initializes a new instance of the <see cref="UploadException"/> class.
    /// </summary>
    /// <param name="message">What went wrong.</param>
    /// <param name="state">Where the upload stands now, so the phone can continue from there.</param>
    public UploadException(string message, UploadState state)
        : base(message)
    {
        State = state;
    }

    /// <summary>
    /// Gets where the upload stands now.
    /// </summary>
    public UploadState State { get; }
}

/// <summary>
/// Files from phones, kept as {root}/{user}/{device}/{yyyy}/{MM}/{name}. Uploads come in
/// chunks and resume after a broken connection; a file already received is never taken twice.
/// Bookkeeping lives in {root}/.homeplay: partial files, and one small index file per finished
/// photo that names where it went.
/// </summary>
public sealed class BackupStore
{
    private static readonly ConcurrentDictionary<string, SemaphoreSlim> Locks = new(StringComparer.Ordinal);

    private readonly string _root;

    /// <summary>
    /// Initializes a new instance of the <see cref="BackupStore"/> class.
    /// </summary>
    /// <param name="root">The backup folder.</param>
    public BackupStore(string root)
    {
        _root = Path.GetFullPath(root);
    }

    private string Meta => Path.Combine(_root, ".homeplay");

    /// <summary>
    /// Where an upload stands.
    /// </summary>
    /// <param name="user">Jellyfin user name.</param>
    /// <param name="device">Phone model, e.g. "Pixel 10a".</param>
    /// <param name="assetId">The phone's own id of the photo or video.</param>
    /// <returns>Finished, or the bytes already received.</returns>
    public UploadState Check(string user, string device, string assetId)
    {
        var (index, part) = Bookkeeping(user, device, assetId);
        if (File.Exists(index))
        {
            return new UploadState(true, 0);
        }

        return new UploadState(false, File.Exists(part) ? new FileInfo(part).Length : 0);
    }

    /// <summary>
    /// Adds a chunk. When the file is complete it moves into its folder.
    /// </summary>
    /// <param name="user">Jellyfin user name.</param>
    /// <param name="device">Phone model.</param>
    /// <param name="assetId">The phone's own id of the photo or video.</param>
    /// <param name="name">File name on the phone.</param>
    /// <param name="size">Size of the whole file.</param>
    /// <param name="takenAt">When the photo was taken; it picks the folder and the file dates.</param>
    /// <param name="offset">Where this chunk starts.</param>
    /// <param name="chunk">The bytes.</param>
    /// <param name="cancellationToken">Cancels the copy.</param>
    /// <returns>Where the upload stands after this chunk.</returns>
    public async Task<UploadState> AppendAsync(
        string user,
        string device,
        string assetId,
        string name,
        long size,
        DateTimeOffset takenAt,
        long offset,
        Stream chunk,
        CancellationToken cancellationToken)
    {
        if (size < 0 || offset < 0 || offset > size)
        {
            throw new UploadException("Bad size or offset", Check(user, device, assetId));
        }

        var (index, part) = Bookkeeping(user, device, assetId);
        var gate = Locks.GetOrAdd(part, _ => new SemaphoreSlim(1, 1));
        await gate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            if (File.Exists(index))
            {
                return new UploadState(true, 0);
            }

            var have = File.Exists(part) ? new FileInfo(part).Length : 0;
            if (offset != have)
            {
                throw new UploadException("The chunk does not start where the last one ended", new UploadState(false, have));
            }

            Directory.CreateDirectory(Path.GetDirectoryName(part)!);
            long written;
            var stream = new FileStream(part, FileMode.Append, FileAccess.Write, FileShare.None, 1 << 16, useAsync: true);
            await using (stream.ConfigureAwait(false))
            {
                await CopyAtMostAsync(chunk, stream, size - have, cancellationToken).ConfigureAwait(false);
                written = stream.Length;
            }

            if (written < size)
            {
                return new UploadState(false, written);
            }

            var target = Place(user, device, name, takenAt);
            File.Move(part, target);
            File.SetCreationTimeUtc(target, takenAt.UtcDateTime);
            File.SetLastWriteTimeUtc(target, takenAt.UtcDateTime);
            Directory.CreateDirectory(Path.GetDirectoryName(index)!);
            await File.WriteAllTextAsync(index, Path.GetRelativePath(_root, target), cancellationToken).ConfigureAwait(false);
            return new UploadState(true, 0);
        }
        finally
        {
            gate.Release();
        }
    }

    /// <summary>
    /// Makes a name safe as one path segment on Windows and Linux: no separators, no "..",
    /// no characters Windows refuses, no reserved device names.
    /// </summary>
    /// <param name="name">Name from the phone.</param>
    /// <param name="fallback">Used when nothing is left.</param>
    /// <returns>The safe name.</returns>
    public static string SafeSegment(string? name, string fallback)
    {
        const string Invalid = "<>:\"/\\|?*";
        var chars = (name ?? string.Empty)
            .Select(c => c < 32 || Invalid.Contains(c, StringComparison.Ordinal) ? '_' : c)
            .ToArray();
        var s = new string(chars).Trim().TrimEnd('.').Trim();
        if (s.Length > 120)
        {
            var ext = Path.GetExtension(s);
            s = string.Concat(s.AsSpan(0, 120 - ext.Length), ext);
        }

        var stem = Path.GetFileNameWithoutExtension(s).ToUpperInvariant();
        string[] reserved = ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "LPT1", "LPT2", "LPT3"];
        if (s.Length == 0 || s.All(c => c == '.' || c == '_') || reserved.Contains(stem))
        {
            return fallback;
        }

        return s;
    }

    /// <summary>
    /// The phone's id goes into a file name; keep it to letters, digits, '-' and '_'.
    /// </summary>
    private static string SafeId(string assetId)
    {
        var s = new string((assetId ?? string.Empty).Select(c => char.IsAsciiLetterOrDigit(c) || c == '-' || c == '_' ? c : '_').ToArray());
        return s.Length is > 0 and <= 200 ? s : throw new UploadException("Bad id", new UploadState(false, 0));
    }

    private static async Task CopyAtMostAsync(Stream from, Stream to, long limit, CancellationToken cancellationToken)
    {
        var buffer = new byte[1 << 16];
        while (limit > 0)
        {
            var read = await from.ReadAsync(buffer.AsMemory(0, (int)Math.Min(buffer.Length, limit)), cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                break;
            }

            await to.WriteAsync(buffer.AsMemory(0, read), cancellationToken).ConfigureAwait(false);
            limit -= read;
        }
    }

    private (string Index, string Part) Bookkeeping(string user, string device, string assetId)
    {
        var u = SafeSegment(user, "user");
        var d = SafeSegment(device, "phone");
        var id = SafeId(assetId);
        return (Path.Combine(Meta, "done", u, d, id), Path.Combine(Meta, "partial", u, d, id + ".part"));
    }

    /// <summary>
    /// A free path in the month folder; "IMG_1.jpg" becomes "IMG_1 (2).jpg" when taken.
    /// </summary>
    private string Place(string user, string device, string name, DateTimeOffset takenAt)
    {
        var local = takenAt.ToLocalTime();
        var folder = Path.Combine(
            _root,
            SafeSegment(user, "user"),
            SafeSegment(device, "phone"),
            local.Year.ToString("D4", CultureInfo.InvariantCulture),
            local.Month.ToString("D2", CultureInfo.InvariantCulture));
        Directory.CreateDirectory(folder);
        var file = SafeSegment(name, "file");
        var stem = Path.GetFileNameWithoutExtension(file);
        var ext = Path.GetExtension(file);
        var target = Path.Combine(folder, file);
        for (var n = 2; File.Exists(target); n++)
        {
            target = Path.Combine(folder, string.Create(CultureInfo.InvariantCulture, $"{stem} ({n}){ext}"));
        }

        return target;
    }
}
