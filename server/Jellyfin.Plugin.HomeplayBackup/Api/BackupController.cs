using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Claims;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.HomeplayBackup.Api;

/// <summary>
/// Upload API for the Homeplay app. Any signed-in user may back up; files go to the user's own folder.
/// </summary>
[ApiController]
[Authorize]
[Route("HomeplayBackup")]
public class BackupController : ControllerBase
{
    /// <summary>
    /// The app sends files in chunks below this, so the default request size limit never bites.
    /// </summary>
    private const long MaxChunk = 64L * 1024 * 1024;

    private readonly ILogger<BackupController> _logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="BackupController"/> class.
    /// </summary>
    /// <param name="logger">Logger.</param>
    public BackupController(ILogger<BackupController> logger)
    {
        _logger = logger;
    }

    /// <summary>
    /// Whether backups can be taken: the app shows "ask the admin to set a folder" otherwise.
    /// </summary>
    /// <returns>Plugin version and whether a folder is set.</returns>
    [HttpGet("Info")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult<BackupInfo> GetInfo() => new BackupInfo(
        typeof(BackupController).Assembly.GetName().Version?.ToString() ?? "0",
        Store() is not null,
        IsFriend());

    /// <summary>
    /// Which of the phone's photos the server already has, and how far partial uploads got.
    /// </summary>
    /// <param name="request">Phone model and photo ids.</param>
    /// <returns>One state per id, in the same order.</returns>
    [HttpPost("Check")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    public ActionResult<IReadOnlyList<AssetState>> Check([FromBody] CheckRequest request)
    {
        if (IsFriend())
        {
            return FriendRefused();
        }

        var store = Store();
        if (store is null)
        {
            return NotConfigured();
        }

        try
        {
            var user = UserName();
            return request.Ids.Select(id =>
            {
                var state = store.Check(user, request.Device, id);
                return new AssetState(id, state.Done, state.Offset);
            }).ToList();
        }
        catch (UploadException e)
        {
            return BadRequest(e.Message);
        }
    }

    /// <summary>
    /// One chunk of a file; the body is the raw bytes. A chunk that does not start where the
    /// server's copy ends gets 409 with the right offset.
    /// </summary>
    /// <param name="device">Phone model.</param>
    /// <param name="id">The phone's id of the photo or video.</param>
    /// <param name="name">File name on the phone.</param>
    /// <param name="size">Size of the whole file.</param>
    /// <param name="takenAt">When it was taken, ISO 8601.</param>
    /// <param name="offset">Where this chunk starts.</param>
    /// <param name="cancellationToken">Request abort.</param>
    /// <returns>Where the upload stands.</returns>
    [HttpPut("Upload")]
    [RequestSizeLimit(MaxChunk)]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    [ProducesResponseType(StatusCodes.Status503ServiceUnavailable)]
    public async Task<ActionResult<AssetState>> Upload(
        [FromQuery] string device,
        [FromQuery] string id,
        [FromQuery] string name,
        [FromQuery] long size,
        [FromQuery] DateTimeOffset takenAt,
        [FromQuery] long offset,
        CancellationToken cancellationToken)
    {
        if (IsFriend())
        {
            return FriendRefused();
        }

        var store = Store();
        if (store is null)
        {
            return NotConfigured();
        }

        try
        {
            var state = await store.AppendAsync(UserName(), device, id, name, size, takenAt, offset, Request.Body, cancellationToken).ConfigureAwait(false);
            if (state.Done)
            {
                _logger.LogInformation("Homeplay backup: {Device} sent {Name}", device, name);
            }

            return new AssetState(id, state.Done, state.Offset);
        }
        catch (UploadException e)
        {
            return Conflict(new AssetState(id, e.State.Done, e.State.Offset));
        }
        catch (IOException e)
        {
            _logger.LogError(e, "Homeplay backup: cannot write {Name}", name);
            return StatusCode(StatusCodes.Status507InsufficientStorage, e.Message);
        }
    }

    private BackupStore? Store()
    {
        var folder = Plugin.Instance?.Configuration.BackupFolder;
        if (string.IsNullOrWhiteSpace(folder))
        {
            return null;
        }

        var store = new BackupStore(folder);
        try
        {
            var moved = store.MoveToMonthFolders();
            if (moved > 0)
            {
                _logger.LogInformation("Homeplay backup: moved {Count} photos into month folders", moved);
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            // Tried again with the next request; uploads go on meanwhile.
            _logger.LogWarning(e, "Homeplay backup: could not move photos into month folders");
        }

        return store;
    }

    private ObjectResult NotConfigured() =>
        StatusCode(StatusCodes.Status503ServiceUnavailable, "The server admin has not set a backup folder for Homeplay Backup yet.");

    private string UserName() => User.FindFirstValue(ClaimTypes.Name) ?? "user";

    // Friends the server is shared with watch and listen; their photos do not go to the owner's computer.
    private bool IsFriend() =>
        Guid.TryParse(User.FindFirstValue("Jellyfin-UserId"), out var id)
        && Plugin.Instance is { } plugin
        && Sharing.SharingStore.IsFriend(plugin.Sharing.Load(), id);

    private ObjectResult FriendRefused() =>
        StatusCode(StatusCodes.Status403Forbidden, "Photo backup is for the server's own people, not for friends it is shared with.");
}

/// <summary>
/// Plugin version and whether a backup folder is set.
/// </summary>
/// <param name="Version">Plugin version.</param>
/// <param name="Configured">A backup folder is set.</param>
/// <param name="Friend">The user is a friend the server is shared with: backups are not for them.</param>
public sealed record BackupInfo(string Version, bool Configured, bool Friend);

/// <summary>
/// Which photos to look up.
/// </summary>
/// <param name="Device">Phone model.</param>
/// <param name="Ids">The phone's ids.</param>
public sealed record CheckRequest(string Device, IReadOnlyList<string> Ids);

/// <summary>
/// Where one upload stands.
/// </summary>
/// <param name="Id">The phone's id.</param>
/// <param name="Done">Finished and in place.</param>
/// <param name="Offset">Bytes already received.</param>
public sealed record AssetState(string Id, bool Done, long Offset);
