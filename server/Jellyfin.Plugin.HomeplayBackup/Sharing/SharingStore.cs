using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
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

    /// <summary>Gets or sets the phone that joined, as it calls itself (e.g. "Google Pixel 10a").</summary>
    public string Device { get; set; } = string.Empty;
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

    /// <summary>
    /// Gets or sets the address last taken from the installer (see <see cref="SharingStore.TakeSuggestion"/>):
    /// an address the owner cleared on purpose is not put back.
    /// </summary>
    public string SuggestionTaken { get; set; } = string.Empty;
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
    /// How a friend uses the server: when they were last seen and what plays for them now.
    /// </summary>
    /// <param name="sessions">The friend's sessions: last activity (UTC) and what plays, if anything.</param>
    /// <param name="userLastActivity">The last activity Jellyfin keeps for the friend's user (UTC).</param>
    /// <param name="now">The time (UTC).</param>
    /// <returns>The last time seen, and what plays now; a session quiet for longer than a few minutes plays nothing.</returns>
    public static FriendActivity Activity(IEnumerable<(DateTime LastActivity, string? NowPlaying)> sessions, DateTime? userLastActivity, DateTime now)
    {
        var list = sessions.ToList();
        DateTime? last = userLastActivity;
        foreach (var (at, _) in list)
        {
            if (last is null || at > last)
            {
                last = at;
            }
        }

        var watching = list
            .Where(s => !string.IsNullOrWhiteSpace(s.NowPlaying) && now - s.LastActivity < TimeSpan.FromMinutes(5))
            .OrderByDescending(s => s.LastActivity)
            .Select(s => s.NowPlaying)
            .FirstOrDefault();
        return new FriendActivity(last, watching);
    }

    /// <summary>
    /// The name of a phone as the owner sees it: trimmed, at most 60 characters.
    /// </summary>
    /// <param name="device">What the phone sent.</param>
    /// <returns>The name; empty when it sent none.</returns>
    public static string DeviceName(string? device)
    {
        var d = (device ?? string.Empty).Trim();
        return d.Length > 60 ? d[..60] : d;
    }

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
    /// What the owner is told when the address works only at home.
    /// </summary>
    public const string HomeOnlyMessage =
        "This address works only at home. Friends need the internet address, like https://your-pc.tail1234.ts.net (Tailscale Funnel).";

    // Names that only the home network knows.
    private static readonly string[] HomeSuffixes = [".local", ".lan", ".home.arpa", ".internal", ".localhost"];

    /// <summary>
    /// Whether <paramref name="input"/> is an address that works only at home, never for a friend
    /// elsewhere: a home network or Tailscale IP (10/8, 172.16/12, 192.168/16, 127/8, 169.254/16,
    /// 100.64/10, fc00::/7, fe80::/10), localhost, a name of one word, or a name in .local, .lan,
    /// .home.arpa or .internal.
    /// </summary>
    /// <param name="input">The address, as typed or as kept; https:// may be missing.</param>
    /// <returns>True when it works only at home; false for an internet address or text that is no address.</returns>
    public static bool IsHomeOnly(string? input)
    {
        var text = input?.Trim() ?? string.Empty;
        if (text.Length == 0)
        {
            return false;
        }

        if (!text.Contains("://", StringComparison.Ordinal))
        {
            text = "https://" + text;
        }

        if (!Uri.TryCreate(text, UriKind.Absolute, out var uri) || uri.Host.Length == 0)
        {
            return false;
        }

        var host = uri.Host.Trim('[', ']').TrimEnd('.').ToLowerInvariant();
        if (IPAddress.TryParse(host, out var ip))
        {
            return IsHomeOnly(ip);
        }

        return host == "localhost"
            || !host.Contains('.', StringComparison.Ordinal)
            || HomeSuffixes.Any(s => host.EndsWith(s, StringComparison.Ordinal) || host == s[1..]);
    }

    private static bool IsHomeOnly(IPAddress ip)
    {
        if (ip.IsIPv4MappedToIPv6)
        {
            ip = ip.MapToIPv4();
        }

        var b = ip.GetAddressBytes();
        if (ip.AddressFamily == AddressFamily.InterNetwork)
        {
            return b[0] == 0 // "this network"
                || b[0] == 10
                || b[0] == 127
                || (b[0] == 172 && b[1] >= 16 && b[1] <= 31)
                || (b[0] == 192 && b[1] == 168)
                || (b[0] == 169 && b[1] == 254)
                || (b[0] == 100 && b[1] >= 64 && b[1] <= 127); // Tailscale
        }

        return ip.Equals(IPAddress.IPv6Loopback)
            || ip.Equals(IPAddress.IPv6Any)
            || (b[0] & 0xFE) == 0xFC // fc00::/7, unique local (Tailscale too)
            || (b[0] == 0xFE && (b[1] & 0xC0) == 0x80); // fe80::/10, link local
    }

    /// <summary>
    /// The file where the installer leaves the server's internet address after turning on Tailscale
    /// Funnel: C:\ProgramData\Homeplay\public-url.txt on Windows.
    /// </summary>
    public static string SuggestionFile =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData), "Homeplay", "public-url.txt");

    /// <summary>
    /// Takes the installer's address as the server's internet address when the owner has none yet
    /// (or only one that works at home) and this address was not taken before. An address that works
    /// only at home is never taken.
    /// </summary>
    /// <param name="state">The sharing, changed in place.</param>
    /// <param name="suggestion">The text of the installer's file, or null without one.</param>
    /// <returns>Whether the state changed.</returns>
    public static bool TakeSuggestion(SharingState state, string? suggestion)
    {
        var url = NormalizeUrl(suggestion);
        if (url is null
            || IsHomeOnly(url)
            || (state.PublicUrl.Length > 0 && !IsHomeOnly(state.PublicUrl))
            || url == state.SuggestionTaken)
        {
            return false;
        }

        state.PublicUrl = url;
        state.SuggestionTaken = url;
        return true;
    }

    /// <summary>
    /// The page on the OwnMedia website that a friend opens. The server and the code go after "#",
    /// which the browser keeps to itself, so the website never learns them.
    /// </summary>
    public const string SiteJoinUrl = "https://ownmedia.app/join.html";

    /// <summary>
    /// The link a friend opens: the invite's page on the OwnMedia website, which offers the app from
    /// the website and hands it the server's address and the code. The server's own page,
    /// /Homeplay/Join/{code}, keeps working for links sent before.
    /// </summary>
    /// <param name="publicUrl">The server's internet address.</param>
    /// <param name="serverName">The server's name, shown on the page.</param>
    /// <param name="code">The invite's code.</param>
    /// <returns>The link.</returns>
    public static string JoinLink(string publicUrl, string serverName, string code)
    {
        var link = $"{SiteJoinUrl}#s={Uri.EscapeDataString(publicUrl.TrimEnd('/'))}";
        if (!string.IsNullOrWhiteSpace(serverName))
        {
            link += $"&n={Uri.EscapeDataString(serverName.Trim())}";
        }

        return $"{link}&c={Uri.EscapeDataString(code)}";
    }

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

/// <summary>How a friend uses the server.</summary>
/// <param name="LastSeen">When they were last seen (UTC), if ever.</param>
/// <param name="Watching">What plays for them now, if anything.</param>
public sealed record FriendActivity(DateTime? LastSeen, string? Watching);
