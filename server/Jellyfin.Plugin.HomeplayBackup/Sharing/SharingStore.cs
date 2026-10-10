using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Jellyfin.Plugin.HomeplayBackup.Sharing;

/// <summary>
/// An invitation for a friend: a one-time code that gives them their own sign-in to the libraries
/// the owner picked.
/// </summary>
public sealed class Invite
{
    /// <summary>Gets or sets the secret code in the link.</summary>
    public string Code { get; set; } = string.Empty;

    /// <summary>Gets or sets the friend's name, as the owner typed it.</summary>
    public string Friend { get; set; } = string.Empty;

    /// <summary>Gets or sets the libraries the friend sees.</summary>
    public List<Guid> Libraries { get; set; } = [];

    /// <summary>Gets or sets when the invite was made (UTC).</summary>
    public DateTime Created { get; set; }

    /// <summary>Gets or sets until when the link works if nobody used it (UTC).</summary>
    public DateTime Expires { get; set; }

    /// <summary>Gets or sets the Jellyfin user made for the friend; empty until they join.</summary>
    public Guid UserId { get; set; }

    /// <summary>Gets or sets when the friend joined (UTC).</summary>
    public DateTime? Joined { get; set; }
}

/// <summary>
/// The owner's sharing: the server's internet address and the invites.
/// </summary>
public sealed class SharingState
{
    /// <summary>Gets or sets the address friends reach the server at, e.g. https://pc.tail1234.ts.net.</summary>
    public string PublicUrl { get; set; } = string.Empty;

    /// <summary>Gets or sets the invites, newest last.</summary>
    public List<Invite> Invites { get; set; } = [];
}

/// <summary>
/// Where an invite stands.
/// </summary>
public enum InviteState
{
    /// <summary>The link works: nobody used it yet.</summary>
    Waiting,

    /// <summary>The friend joined; the link no longer works.</summary>
    Joined,

    /// <summary>Nobody used it in time.</summary>
    Expired,

    /// <summary>No such code.</summary>
    Unknown,
}

/// <summary>
/// The sharing settings in a file of the plugin's own (sharing.json), apart from the plugin's
/// settings so that saving those never drops an invite.
/// </summary>
public sealed class SharingStore
{
    private static readonly object Gate = new();

    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };

    // No 0/O, 1/I/L: the code may be read out or typed.
    private const string Alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

    private readonly string _file;

    /// <summary>
    /// Initializes a new instance of the <see cref="SharingStore"/> class.
    /// </summary>
    /// <param name="file">The file the state lives in.</param>
    public SharingStore(string file)
    {
        _file = file;
    }

    /// <summary>
    /// The state as saved; empty when there is none yet.
    /// </summary>
    /// <returns>The state.</returns>
    public SharingState Load()
    {
        lock (Gate)
        {
            return Read();
        }
    }

    /// <summary>
    /// Changes the state and saves it, one change at a time.
    /// </summary>
    /// <typeparam name="T">What the change gives back.</typeparam>
    /// <param name="change">The change.</param>
    /// <returns>What <paramref name="change"/> returned.</returns>
    public T Update<T>(Func<SharingState, T> change)
    {
        lock (Gate)
        {
            var state = Read();
            var result = change(state);
            Directory.CreateDirectory(Path.GetDirectoryName(_file)!);
            var temp = _file + ".tmp";
            File.WriteAllText(temp, JsonSerializer.Serialize(state, Json), Encoding.UTF8);
            File.Move(temp, _file, true);
            return result;
        }
    }

    private SharingState Read() => File.Exists(_file)
        ? JsonSerializer.Deserialize<SharingState>(File.ReadAllText(_file, Encoding.UTF8)) ?? new SharingState()
        : new SharingState();

    /// <summary>
    /// A new secret code: 20 characters, about 100 bits, too many to guess.
    /// </summary>
    /// <returns>The code.</returns>
    public static string NewCode() =>
        new(Enumerable.Range(0, 20).Select(_ => Alphabet[RandomNumberGenerator.GetInt32(Alphabet.Length)]).ToArray());

    /// <summary>
    /// A random password for a friend's sign-in: they never see or type it; the app keeps the token.
    /// </summary>
    /// <returns>The password.</returns>
    public static string NewPassword() => Convert.ToBase64String(RandomNumberGenerator.GetBytes(24));

    /// <summary>
    /// Where <paramref name="invite"/> stands at <paramref name="now"/>.
    /// </summary>
    /// <param name="invite">The invite, or null for an unknown code.</param>
    /// <param name="now">The time (UTC).</param>
    /// <returns>Its state.</returns>
    public static InviteState StateOf(Invite? invite, DateTime now) => invite switch
    {
        null => InviteState.Unknown,
        { UserId: var id } when id != Guid.Empty => InviteState.Joined,
        { Expires: var until } when now > until => InviteState.Expired,
        _ => InviteState.Waiting,
    };

    /// <summary>
    /// The invite with <paramref name="code"/>, typed in any case.
    /// </summary>
    /// <param name="state">The state.</param>
    /// <param name="code">The code.</param>
    /// <returns>The invite, or null.</returns>
    public static Invite? Find(SharingState state, string code) =>
        state.Invites.FirstOrDefault(i => string.Equals(i.Code, code.Trim(), StringComparison.OrdinalIgnoreCase));

    /// <summary>
    /// Whether <paramref name="userId"/> is a friend's sign-in, made by an invite.
    /// </summary>
    /// <param name="state">The state.</param>
    /// <param name="userId">The user.</param>
    /// <returns>True for a friend.</returns>
    public static bool IsFriend(SharingState state, Guid userId) =>
        userId != Guid.Empty && state.Invites.Any(i => i.UserId == userId);

    /// <summary>
    /// The address as typed made into a site address: https:// added when missing, no trailing
    /// slash. Null when it is not one.
    /// </summary>
    /// <param name="input">What the owner typed.</param>
    /// <returns>The address, or null.</returns>
    public static string? NormalizeUrl(string? input)
    {
        var text = input?.Trim() ?? string.Empty;
        if (text.Length == 0)
        {
            return null;
        }

        if (!text.Contains("://", StringComparison.Ordinal))
        {
            text = "https://" + text;
        }

        return Uri.TryCreate(text, UriKind.Absolute, out var uri)
            && (uri.Scheme == Uri.UriSchemeHttps || uri.Scheme == Uri.UriSchemeHttp)
            && uri.Host.Contains('.', StringComparison.Ordinal)
            ? uri.GetLeftPart(UriPartial.Path).TrimEnd('/')
            : null;
    }

    /// <summary>
    /// The link a friend opens: the server's page for the invite.
    /// </summary>
    /// <param name="publicUrl">The server's internet address.</param>
    /// <param name="code">The invite's code.</param>
    /// <returns>The link.</returns>
    public static string JoinLink(string publicUrl, string code) => $"{publicUrl.TrimEnd('/')}/Homeplay/Join/{code}";

    /// <summary>
    /// A user name for the friend that Jellyfin takes and nobody has: their name in plain
    /// characters, then "Name 2", "Name 3"...
    /// </summary>
    /// <param name="friend">The friend's name.</param>
    /// <param name="taken">Whether a name is in use.</param>
    /// <returns>The user name.</returns>
    public static string UserNameFor(string friend, Func<string, bool> taken)
    {
        var clean = new string(friend.Where(c => char.IsLetterOrDigit(c) || c is ' ' or '-' or '_' or '.' or '\'').ToArray()).Trim();
        if (clean.Length == 0)
        {
            clean = "Friend";
        }

        if (clean.Length > 40)
        {
            clean = clean[..40].Trim();
        }

        var name = clean;
        for (var n = 2; taken(name); n++)
        {
            name = $"{clean} {n}";
        }

        return name;
    }
}
