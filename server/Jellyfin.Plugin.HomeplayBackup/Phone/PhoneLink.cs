using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;

namespace Jellyfin.Plugin.HomeplayBackup.Phone;

/// <summary>
/// How a phone on the home Wi-Fi reaches this computer to fetch the app: the address to put in
/// the QR code and the app file shipped next to the plugin.
/// </summary>
public static class PhoneLink
{
    /// <summary>
    /// The file name the app is served and saved under.
    /// </summary>
    public const string ApkName = "Homeplay.apk";

    /// <summary>
    /// The app in Google Play: where phones get it when no app file came with the plugin (a
    /// plugin from the store era ships without one).
    /// </summary>
    public const string PlayStoreUrl = "https://play.google.com/store/apps/details?id=dev.homeplay.homeplay";

    /// <summary>
    /// Where a phone gets the app: the file on this server when it has one, else Google Play.
    /// </summary>
    /// <param name="server">The server's address as the phone reaches it.</param>
    /// <param name="hasApk">Whether the app file lies next to the plugin.</param>
    /// <returns>The address.</returns>
    public static string AppUrl(string server, bool hasApk) => hasApk ? $"{server.TrimEnd('/')}/Homeplay/App" : PlayStoreUrl;

    /// <summary>
    /// The address of this computer in the home network: on an adapter with a router (not a
    /// virtual machine's), 192.168.x.x first, then 10.x.x.x, then 172.16–31.x.x. Not loopback,
    /// not link-local (169.254), not Tailscale or carrier addresses (100.64/10), and not IPv6,
    /// which phones type and scan badly.
    /// </summary>
    /// <param name="addresses">The computer's addresses, each with whether its adapter has a gateway.</param>
    /// <returns>The best one, or null without a home network.</returns>
    public static IPAddress? PickLanAddress(IEnumerable<(IPAddress Address, bool HasGateway)> addresses) => addresses
        .Where(a => a.Address.AddressFamily == AddressFamily.InterNetwork)
        .Select(a => (a.Address, a.HasGateway, Rank: Rank(a.Address.GetAddressBytes())))
        .Where(a => a.Rank > 0)
        .OrderByDescending(a => a.HasGateway)
        .ThenBy(a => a.Rank)
        .Select(a => a.Address)
        .FirstOrDefault();

    private static int Rank(byte[] b) => b switch
    {
        [192, 168, ..] => 1,
        [10, ..] => 2,
        [172, >= 16 and <= 31, ..] => 3,
        _ => 0,
    };

    /// <summary>
    /// Whether a host name is this computer itself: then the page was opened on the computer and
    /// the QR code needs its network address instead.
    /// </summary>
    /// <param name="host">Host the page was asked for.</param>
    /// <returns>True for localhost and loopback addresses.</returns>
    public static bool IsLoopback(string host) =>
        string.Equals(host, "localhost", StringComparison.OrdinalIgnoreCase)
        || (IPAddress.TryParse(host.Trim('[', ']'), out var ip) && IPAddress.IsLoopback(ip));

    /// <summary>
    /// The server address the phone app connects to, e.g. "http://192.168.1.10:8096".
    /// </summary>
    /// <param name="host">Host name or address.</param>
    /// <param name="port">Port.</param>
    /// <returns>The address.</returns>
    public static string ServerUrl(string host, int port) => $"http://{host}:{port}";

    /// <summary>
    /// The app file next to the plugin: Homeplay.apk, else any other .apk (e.g. Homeplay-0.2.0.apk).
    /// </summary>
    /// <param name="folder">The plugin's folder.</param>
    /// <returns>The file's path, or null when there is none.</returns>
    public static string? FindApk(string folder)
    {
        if (!Directory.Exists(folder))
        {
            return null;
        }

        var exact = Path.Combine(folder, ApkName);
        return File.Exists(exact)
            ? exact
            : Directory.GetFiles(folder, "*.apk").OrderByDescending(f => f, StringComparer.Ordinal).FirstOrDefault();
    }

    /// <summary>
    /// The page shown on the computer after setup: a QR code to scan with the phone, and what to do next.
    /// </summary>
    /// <param name="serverName">The server's name, as the app will find it.</param>
    /// <param name="serverUrl">The server address, for typing it in by hand.</param>
    /// <param name="qrPng">The QR code of the app's address, as PNG; null when there is no app file.</param>
    /// <returns>The HTML page.</returns>
    public static string Page(string serverName, string serverUrl, byte[]? qrPng)
    {
        var name = WebUtility.HtmlEncode(serverName);
        var url = WebUtility.HtmlEncode(serverUrl);
        var qr = qrPng is null
            ? "<p class=\"warn\">No QR code could be made. Get Homeplay from Google Play on the phone.</p>"
            : $"<img class=\"qr\" alt=\"QR code: the Homeplay app for Android\" src=\"data:image/png;base64,{Convert.ToBase64String(qrPng)}\">";
        return $$"""
            <!doctype html>
            <html lang="en">
            <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Homeplay: connect your phone</title>
            <style>
              :root { color-scheme: light dark; --bg: #f6f4fb; --card: #fff; --text: #1c1b20; --muted: #5d5a66; --accent: #6750a4; }
              @media (prefers-color-scheme: dark) { :root { --bg: #141218; --card: #211f26; --text: #e6e0e9; --muted: #cac4d0; --accent: #d0bcff; } }
              body { margin: 0; background: var(--bg); color: var(--text); font: 17px/1.5 system-ui, sans-serif; }
              main { max-width: 720px; margin: 0 auto; padding: 32px 16px; }
              h1 { font-size: 32px; margin: 0 0 4px; }
              .lead { color: var(--muted); margin: 0 0 24px; }
              .card { background: var(--card); border-radius: 24px; padding: 24px; display: flex; gap: 24px; align-items: center; flex-wrap: wrap; }
              .qr { width: 240px; height: 240px; image-rendering: pixelated; background: #fff; border-radius: 12px; padding: 8px; }
              ol { margin: 0; padding-left: 22px; flex: 1; min-width: 260px; }
              li { margin: 0 0 12px; }
              b { color: var(--accent); }
              code { font-size: 18px; }
              .warn { color: #b3261e; flex: 1; }
            </style>
            </head>
            <body>
            <main>
              <h1>Your server is ready</h1>
              <p class="lead">Movies, shows, music and photos on this computer, now on your phone.</p>
              <div class="card">
                {{qr}}
                <ol>
                  <li>Connect the phone to the same Wi-Fi as this computer.</li>
                  <li>Point the phone's camera at the code and open the link. The Homeplay app downloads from this computer.</li>
                  <li>Open the file and tap <b>Install</b>. If the phone asks, allow installing from this source.</li>
                  <li>Open Homeplay and tap <b>Add your server</b>. It finds <b>{{name}}</b> by itself: enter your name and password.</li>
                </ol>
              </div>
              <p class="lead">Server address, if the phone does not find it: <code>{{url}}</code></p>
            </main>
            </body>
            </html>
            """;
    }
}
