using System;
using System.Collections.Generic;
using System.Net;

namespace Jellyfin.Plugin.HomeplayBackup.Sharing;

/// <summary>
/// The page a friend's invite link opens on their phone: one button that opens Homeplay with the
/// invite, or downloads the app first when it is not there.
/// </summary>
public static class JoinPage
{
    /// <summary>
    /// The app's own link for an invite: Homeplay adds the server from it.
    /// </summary>
    /// <param name="server">The server's internet address.</param>
    /// <param name="code">The invite's code.</param>
    /// <returns>A homeplay:// link.</returns>
    public static string AppLink(string server, string code) =>
        $"homeplay://join?server={Uri.EscapeDataString(server)}&code={Uri.EscapeDataString(code)}";

    /// <summary>
    /// The same for Chrome on Android: it opens Homeplay, or without it goes to <paramref name="appUrl"/>
    /// to download the app.
    /// </summary>
    /// <param name="server">The server's internet address.</param>
    /// <param name="code">The invite's code.</param>
    /// <param name="appUrl">Where the app downloads from.</param>
    /// <returns>An intent:// link.</returns>
    public static string IntentLink(string server, string code, string appUrl) =>
        $"intent://join?server={Uri.EscapeDataString(server)}&code={Uri.EscapeDataString(code)}" +
        $"#Intent;scheme=homeplay;package=dev.homeplay.homeplay;S.browser_fallback_url={Uri.EscapeDataString(appUrl)};end";

    /// <summary>
    /// How to make a server of one's own: three steps, with the installer from this server when
    /// it has one.
    /// </summary>
    /// <param name="setupUrl">Where the installer downloads from, or null.</param>
    /// <returns>An HTML card.</returns>
    public static string OwnServer(string? setupUrl)
    {
        var download = setupUrl is null
            ? "Ask whoever sent you this link for the file <b>HomeplaySetup.exe</b> and run it on your Windows computer."
            : $"On your Windows computer, open this page and <a href=\"{WebUtility.HtmlEncode(setupUrl)}\">download HomeplaySetup</a>. Run it.";
        return $"""
            <div class="card own">
            <h2>Your own Homeplay</h2>
            <p class="lead">Your movies, music and photos from your computer on your phone. Free, and nothing goes to the cloud.</p>
            <ol>
              <li>{download}</li>
              <li>Choose the folders with your movies, music and photos, a name and a password. It sets everything up by itself.</li>
              <li>At the end it shows a QR code: point your phone's camera at it. Or in Homeplay tap <b>Add your server</b>: it finds your computer on your Wi-Fi.</li>
            </ol>
            </div>
            """;
    }

    /// <summary>
    /// The page for <paramref name="state"/>.
    /// </summary>
    /// <param name="state">Where the invite stands.</param>
    /// <param name="serverName">The server's name.</param>
    /// <param name="libraries">The names of the libraries the invite opens.</param>
    /// <param name="server">The server's internet address.</param>
    /// <param name="code">The invite's code.</param>
    /// <param name="appUrl">Where the app comes from: the file on the server, or Google Play.</param>
    /// <param name="setupUrl">Where the server installer downloads from; null when this server has none.</param>
    /// <returns>The HTML page.</returns>
    public static string Html(InviteState state, string serverName, IReadOnlyList<string> libraries, string server, string code, string appUrl, string? setupUrl = null)
    {
        var name = WebUtility.HtmlEncode(serverName);
        var store = appUrl.Contains("play.google.com", StringComparison.Ordinal);
        var body = state switch
        {
            InviteState.Waiting => $"""
                <h1>{name}</h1>
                <p class="lead">You are invited to watch and listen: {WebUtility.HtmlEncode(string.Join(", ", libraries))}.</p>
                <a class="button" href="{WebUtility.HtmlEncode(IntentLink(server, code, appUrl))}">Open in Homeplay</a>
                <p class="small">No Homeplay on this phone yet? The button {(store ? "opens it in Google Play" : "downloads it")}. Install it, then come back to this page and tap the button again.</p>
                <p class="small"><a href="{WebUtility.HtmlEncode(AppLink(server, code))}">Open in Homeplay</a> (if the button does nothing) · <a href="{WebUtility.HtmlEncode(appUrl)}">{(store ? "Get Homeplay on Google Play" : "Download Homeplay for Android")}</a></p>
                <p class="small">Or in Homeplay: Add your server → Have an invite link? → paste this page's address.</p>
                """,
            InviteState.Joined => $"""
                <h1>{name}</h1>
                <p class="lead">This invite has been used already. If it was not you, ask whoever sent it for a new one.</p>
                """,
            InviteState.Expired => $"""
                <h1>{name}</h1>
                <p class="lead">This invite has expired. Ask whoever sent it for a new one.</p>
                """,
            _ => """
                <h1>Homeplay</h1>
                <p class="lead">There is no such invite. Check the link, or ask whoever sent it for a new one.</p>
                """,
        };
        return $$"""
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <meta name="robots" content="noindex">
            <title>Homeplay invite</title>
            <style>
              :root { color-scheme: light dark; --bg: #f6f4fb; --card: #fff; --text: #1c1b20; --muted: #5d5a66; --accent: #6750a4; --on-accent: #fff; }
              @media (prefers-color-scheme: dark) { :root { --bg: #141218; --card: #211f26; --text: #e6e0e9; --muted: #cac4d0; --accent: #d0bcff; --on-accent: #381e72; } }
              body { margin: 0; background: var(--bg); color: var(--text); font: 17px/1.5 system-ui, sans-serif; }
              main { max-width: 560px; margin: 0 auto; padding: 40px 16px; }
              .card { background: var(--card); border-radius: 24px; padding: 28px 24px; }
              h1 { font-size: 28px; margin: 0 0 8px; }
              .lead { color: var(--muted); margin: 0 0 24px; }
              .button { display: block; text-align: center; background: var(--accent); color: var(--on-accent); text-decoration: none; font-weight: 600; padding: 16px; border-radius: 999px; font-size: 19px; }
              .small { color: var(--muted); font-size: 15px; margin: 16px 0 0; }
              .own { margin-top: 16px; }
              h2 { font-size: 22px; margin: 0 0 8px; }
              ol { margin: 0; padding-left: 22px; }
              li { margin: 0 0 10px; }
              a { color: var(--accent); }
            </style>
            </head>
            <body>
            <main><div class="card">
            {{body}}
            </div>
            {{OwnServer(setupUrl)}}
            </main>
            </body>
            </html>
            """;
    }
}
