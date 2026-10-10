using System.IO;
using System.Linq;
using System.Net.NetworkInformation;
using Jellyfin.Plugin.HomeplayBackup.Phone;
using MediaBrowser.Controller;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using QRCoder;

namespace Jellyfin.Plugin.HomeplayBackup.Api;

/// <summary>
/// Getting the app onto a phone: a page on the computer with a QR code, and the app file itself.
/// Open to everyone, since the phone has no account yet; it gives out nothing but the app.
/// </summary>
[ApiController]
[AllowAnonymous]
[Route("Homeplay")]
public class PhoneController : ControllerBase
{
    private readonly IServerApplicationHost _host;

    /// <summary>
    /// Initializes a new instance of the <see cref="PhoneController"/> class.
    /// </summary>
    /// <param name="host">The server, for its name.</param>
    public PhoneController(IServerApplicationHost host)
    {
        _host = host;
    }

    private static string PluginFolder => Path.GetDirectoryName(typeof(PhoneController).Assembly.Location) ?? ".";

    /// <summary>
    /// The page to open on the computer after setup: scan the code with the phone.
    /// </summary>
    /// <returns>An HTML page.</returns>
    [HttpGet("Phone")]
    [Produces("text/html")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ContentResult Page()
    {
        var host = Request.Host.Host;
        if (PhoneLink.IsLoopback(host))
        {
            host = PhoneLink.PickLanAddress(LocalAddresses())?.ToString() ?? host;
        }

        var server = PhoneLink.ServerUrl(host, Request.Host.Port ?? HttpContext.Connection.LocalPort);
        var appUrl = PhoneLink.AppUrl(server, PhoneLink.FindApk(PluginFolder) is not null);
        var png = PngByteQRCodeHelper.GetQRCode(appUrl, QRCodeGenerator.ECCLevel.M, 10);
        return Content(PhoneLink.Page(_host.FriendlyName, server, png), "text/html; charset=utf-8");
    }

    /// <summary>
    /// The server installer for Windows, for a friend who wants a Homeplay server of their own.
    /// </summary>
    /// <returns>HomeplaySetup.exe.</returns>
    [HttpGet("Setup")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public ActionResult Setup()
    {
        var setup = PhoneLink.FindSetup(PluginFolder);
        return setup is null
            ? NotFound("The Homeplay installer is not on this server.")
            : PhysicalFile(setup, "application/vnd.microsoft.portable-executable", PhoneLink.SetupName);
    }

    /// <summary>
    /// The Homeplay app for Android.
    /// </summary>
    /// <returns>The APK file.</returns>
    [HttpGet("App")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public ActionResult App()
    {
        var apk = PhoneLink.FindApk(PluginFolder);
        return apk is null
            ? NotFound("The Homeplay app is not on this server.")
            : PhysicalFile(apk, "application/vnd.android.package-archive", PhoneLink.ApkName);
    }

    private static System.Collections.Generic.IEnumerable<(System.Net.IPAddress, bool)> LocalAddresses() =>
        NetworkInterface.GetAllNetworkInterfaces()
            .Where(n => n.OperationalStatus == OperationalStatus.Up)
            .SelectMany(n =>
            {
                var props = n.GetIPProperties();
                var gateway = props.GatewayAddresses.Any(g => !g.Address.Equals(System.Net.IPAddress.Any));
                return props.UnicastAddresses.Select(u => (u.Address, gateway));
            });
}
