using System;
using Jellyfin.Plugin.HomeplayBackup.Sharing;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.HomeplayBackup.Api;

/// <summary>
/// OwnMedia Pro on this server: the owner's app leaves the purchase here, and friends invited to
/// the server watch free once their apps find it and check Google's signature.
/// </summary>
[ApiController]
[Route("Homeplay")]
public class LicenceController : ControllerBase
{
    private static SharingStore Store => Plugin.Instance?.Sharing ?? throw new InvalidOperationException("Homeplay plugin not loaded");

    /// <summary>
    /// The owner's purchase, for anyone signed in to the server.
    /// </summary>
    /// <returns>The purchase, or 204 when there is none.</returns>
    [HttpGet("Licence")]
    [Authorize]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    public ActionResult<ProLicence> GetLicence() => Store.Load().Licence is { } licence ? licence : NoContent();

    /// <summary>
    /// Keeps the owner's purchase. Only the owner (an administrator) may.
    /// </summary>
    /// <param name="licence">The purchase as Google Play gave it.</param>
    /// <returns>204 when kept.</returns>
    [HttpPost("Licence")]
    [Authorize(Policy = "RequiresElevation")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public ActionResult SetLicence([FromBody] ProLicence licence)
    {
        if (licence is null || !licence.LooksRight())
        {
            return BadRequest("That is not a purchase of OwnMedia Pro.");
        }

        Store.Update(s => s.Licence = licence);
        return NoContent();
    }
}
