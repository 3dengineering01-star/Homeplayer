using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Xunit;

namespace Jellyfin.Plugin.HomeplayBackup.Tests;

public sealed class BackupStoreTests : IDisposable
{
    private static readonly DateTimeOffset Taken = new(2026, 10, 6, 12, 30, 0, TimeSpan.Zero);

    private readonly string _root = Path.Combine(Path.GetTempPath(), "homeplay-test-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_root))
        {
            Directory.Delete(_root, true);
        }
    }

    private static MemoryStream Bytes(string s) => new(Encoding.ASCII.GetBytes(s));

    private Task<UploadState> Send(BackupStore store, string id, string name, string content, long size, long offset) =>
        store.AppendAsync("anna", "Pixel 10a", id, name, size, Taken, offset, Bytes(content), CancellationToken.None);

    private string[] Photos() => Directory.GetFiles(_root, "*", SearchOption.AllDirectories)
        .Select(f => Path.GetRelativePath(_root, f).Replace('\\', '/'))
        .Where(f => !f.StartsWith(".homeplay/", StringComparison.Ordinal))
        .OrderBy(f => f, StringComparer.Ordinal)
        .ToArray();

    [Fact]
    public async Task WholeFileLandsInTheMonthItWasTaken()
    {
        var store = new BackupStore(_root);
        Assert.Equal(new UploadState(false, 0), store.Check("anna", "Pixel 10a", "101"));

        Assert.Equal(new UploadState(true, 0), await Send(store, "101", "PXL_1.jpg", "hello", 5, 0));

        var photo = Path.Combine(_root, "2026-10", "PXL_1.jpg");
        Assert.Equal("hello", File.ReadAllText(photo));
        Assert.Equal(Taken.UtcDateTime, File.GetLastWriteTimeUtc(photo));
        Assert.Equal(new UploadState(true, 0), store.Check("anna", "Pixel 10a", "101"));
    }

    [Fact]
    public async Task ChunksResumeWhereTheServerCopyEnds()
    {
        var store = new BackupStore(_root);
        Assert.Equal(new UploadState(false, 4), await Send(store, "7", "VID.mp4", "abcd", 10, 0));
        Assert.Equal(new UploadState(false, 4), store.Check("anna", "Pixel 10a", "7"));
        Assert.Empty(Photos());

        // The phone lost the answer and resends from 0: told to continue from 4.
        var e = await Assert.ThrowsAsync<UploadException>(() => Send(store, "7", "VID.mp4", "abcd", 10, 0));
        Assert.Equal(new UploadState(false, 4), e.State);

        Assert.Equal(new UploadState(true, 0), await Send(store, "7", "VID.mp4", "efghij", 10, 4));
        Assert.Equal(["2026-10/VID.mp4"], Photos());
        Assert.Equal("abcdefghij", File.ReadAllText(Path.Combine(_root, "2026-10/VID.mp4")));
    }

    [Fact]
    public async Task ExtraBytesBeyondTheSizeAreIgnored()
    {
        var store = new BackupStore(_root);
        Assert.Equal(new UploadState(true, 0), await Send(store, "1", "a.jpg", "12345678", 3, 0));
        Assert.Equal("123", File.ReadAllText(Path.Combine(_root, "2026-10/a.jpg")));
    }

    [Fact]
    public async Task AFinishedPhotoIsNeverTakenTwice()
    {
        var store = new BackupStore(_root);
        await Send(store, "1", "a.jpg", "one", 3, 0);
        Assert.Equal(new UploadState(true, 0), await Send(store, "1", "a.jpg", "two", 3, 0));
        Assert.Equal(["2026-10/a.jpg"], Photos());
        Assert.Equal("one", File.ReadAllText(Path.Combine(_root, "2026-10/a.jpg")));
    }

    [Fact]
    public async Task SameNameFromAnotherPhotoGetsANumber()
    {
        var store = new BackupStore(_root);
        await Send(store, "1", "IMG.jpg", "one", 3, 0);
        await Send(store, "2", "IMG.jpg", "two", 3, 0);
        Assert.Equal(["2026-10/IMG (2).jpg", "2026-10/IMG.jpg"], Photos());
    }

    [Fact]
    public async Task NamesCannotEscapeTheFolder()
    {
        var store = new BackupStore(_root);
        await store.AppendAsync("../../etc", "..", "x", "../../evil.sh", 1, Taken, 0, Bytes("x"), CancellationToken.None);
        Assert.Equal(["2026-10/.._.._evil.sh"], Photos());
        Assert.Equal(new UploadState(false, 0), store.Check("anna", "p", "../x")); // becomes ___x
        Assert.Throws<UploadException>(() => store.Check("anna", "p", string.Empty));
    }

    [Theory]
    [InlineData("PXL_20261006.jpg", "PXL_20261006.jpg")]
    [InlineData("a/b\\c:d*e?.jpg", "a_b_c_d_e_.jpg")]
    [InlineData("  name. ", "name")]
    [InlineData("CON.jpg", "fallback")]
    [InlineData("..", "fallback")]
    [InlineData("", "fallback")]
    [InlineData(null, "fallback")]
    public void SafeSegment(string? name, string expected) => Assert.Equal(expected, BackupStore.SafeSegment(name, "fallback"));

    [Fact]
    public async Task BadOffsetsAreRefused()
    {
        var store = new BackupStore(_root);
        await Assert.ThrowsAsync<UploadException>(() => Send(store, "1", "a.jpg", "x", 3, 5));
        await Assert.ThrowsAsync<UploadException>(() => Send(store, "1", "a.jpg", "x", -1, 0));
    }

    [Fact]
    public async Task PhotosKeptTheOldWayMoveIntoMonthFolders()
    {
        // Two photos the old version put in {user}/{device}/{yyyy}/{MM}, one of them with a name
        // a new photo already has; and a file of the user's own that the store did not put there.
        var old = Path.Combine(_root, "anna", "Pixel 10a", "2026", "09");
        Directory.CreateDirectory(old);
        File.WriteAllText(Path.Combine(old, "a.jpg"), "old a");
        File.WriteAllText(Path.Combine(old, "b.jpg"), "old b");
        Directory.CreateDirectory(Path.Combine(_root, "anna", "Pixel 10a", "2026", "10"));
        File.WriteAllText(Path.Combine(_root, "anna", "Pixel 10a", "2026", "10", "mine.txt"), "keep");
        var index = Path.Combine(_root, ".homeplay", "done", "anna", "Pixel 10a");
        Directory.CreateDirectory(index);
        File.WriteAllText(Path.Combine(index, "1"), "anna/Pixel 10a/2026/09/a.jpg");
        File.WriteAllText(Path.Combine(index, "2"), "anna\\Pixel 10a\\2026\\09\\b.jpg");
        Directory.CreateDirectory(Path.Combine(_root, "2026-09"));
        File.WriteAllText(Path.Combine(_root, "2026-09", "b.jpg"), "new b");

        var store = new BackupStore(_root);
        Assert.Equal(2, store.MoveToMonthFolders());

        Assert.Equal(["2026-09/a.jpg", "2026-09/b (2).jpg", "2026-09/b.jpg", "anna/Pixel 10a/2026/10/mine.txt"], Photos());
        Assert.Equal("old b", File.ReadAllText(Path.Combine(_root, "2026-09", "b (2).jpg")));
        Assert.Equal(Path.Combine("2026-09", "a.jpg"), File.ReadAllText(Path.Combine(index, "1")));
        Assert.False(Directory.Exists(old));
        Assert.Equal(new UploadState(true, 0), store.Check("anna", "Pixel 10a", "1"));

        // Once only.
        Assert.Equal(0, store.MoveToMonthFolders());
    }

    [Fact]
    public void NothingToMoveOnAFreshFolder() => Assert.Equal(0, new BackupStore(_root).MoveToMonthFolders());
}
