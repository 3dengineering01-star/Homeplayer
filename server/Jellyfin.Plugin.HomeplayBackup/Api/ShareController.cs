using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Jellyfin.Plugin.HomeplayBackup.Phone;
using Jellyfin.Plugin.HomeplayBackup.Sharing;
using MediaBrowser.Controller;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.HomeplayBackup.Api;

/// <summary>
/// Sharing the server with friends: the owner makes an invite link for chosen libraries; a friend
/// who opens it gets a sign-in of their own, that sees only those libraries and deletes nothing.
/// </summary>
[ApiController]
[Route("Homeplay")]
public class ShareController : ControllerBase
{
    /// <summary>One join at a time: an invite is used once.</summary>
    private static readonly SemaphoreSlim JoinGate = new(1, 1);

    private readonly IServerApplicationHost _host;
    private readonly IUserManager _users;
    private readonly ISessionManager _sessions;
    private readonly ILibraryManager _libraries;
    private readonly ILogger<ShareController> _logger;

    /// <summary>
    /// Initializes a new instance of the <see cref="ShareController"/> class.
    /// </summary>
    /// <param name="host">The server, for its name.</param>
    /// <param name="users">Users, to make the friends' sign-ins.</param>
    /// <param name="sessions">Sessions, to sign the friend's phone in.</param>
    /// <param name="libraries">Libraries, to name them.</param>
    /// <param name="logger">Logger.</param>
    public ShareController(IServerApplicationHost host, IUserManager users, ISessionManager sessions, ILibraryManager libraries, ILogger<ShareController> logger)
    {
        _host = host;
        _users = users;
        _sessions = sessions;
        _libraries = libraries;
        _logger = logger;
    }

    private static SharingStore Store => Plugin.Instance?.Sharing ?? throw new InvalidOperationException("Homeplay plugin not loaded");

    private List<LibraryInfo> Libraries() => _libraries.GetVirtualFolders()
        .Where(f => Guid.TryParse(f.ItemId, out _))
        .Select(f => new LibraryInfo(Guid.Parse(f.ItemId), f.Name, f.CollectionType?.ToString().ToLowerInvariant()))
        .ToList();

    private InviteInfo Info(SharingState state, Invite i, IReadOnlyList<LibraryInfo> libraries) => new(
        i.Code,
        i.Friend,
        i.Libraries,
        [.. i.Libraries.Select(id => libraries.FirstOrDefault(l => l.Id == id)?.Name).OfType<string>()],
        i.Created,
        i.Expires,
        i.Joined,
        SharingStore.StateOf(i, DateTime.UtcNow).ToString(),
        state.PublicUrl.Length == 0 ? string.Empty : SharingStore.JoinLink(state.PublicUrl, i.Code));

    /// <summary>
    /// The owner's sharing: the internet address, the libraries there are and the invites.
    /// </summary>
    /// <returns>The sharing.</returns>
    [HttpGet("Sharing")]
    [Authorize(Policy = "RequiresElevation")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ActionResult<SharingInfo> GetSharing()
    {
        var state = Store.Load();
        var libraries = Libraries();
        return new SharingInfo(state.PublicUrl, libraries, [.. state.Invites.Select(i => Info(state, i, libraries))]);
    }

    /// <summary>
    /// Sets the address friends reach the server at; empty to clear it.
    /// </summary>
    /// <param name="request">The address.</param>
    /// <returns>The address as kept.</returns>
    [HttpPost("Sharing")]
    [Authorize(Policy = "RequiresElevation")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public ActionResult<string> SetSharing([FromBody] SharingRequest request)
    {
        var url = string.IsNullOrWhiteSpace(request.PublicUrl) ? string.Empty : SharingStore.NormalizeUrl(request.PublicUrl);
        if (url is null)
        {
            return BadRequest("That is not a web address. It looks like https://your-pc.tail1234.ts.net");
        }

        Store.Update(s => s.PublicUrl = url);
        return url;
    }

    /// <summary>
    /// A new invite link for a friend.
    /// </summary>
    /// <param name="request">The friend's name, the libraries and how many days the link works.</param>
    /// <returns>The invite with its link.</returns>
    [HttpPost("Invites")]
    [Authorize(Policy = "RequiresElevation")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status409Conflict)]
    public ActionResult<InviteInfo> CreateInvite([FromBody] InviteRequest request)
    {
        var libraries = Libraries();
        var chosen = request.Libraries.Where(id => libraries.Any(l => l.Id == id)).Distinct().ToList();
        if (chosen.Count == 0)
        {
            return BadRequest("Choose at least one library to share.");
        }

        var now = DateTime.UtcNow;
        var result = Store.Update(state =>
        {
            if (state.PublicUrl.Length == 0)
            {
                return null;
            }

            var invite = new Invite
            {
                Code = SharingStore.NewCode(),
                Friend = string.IsNullOrWhiteSpace(request.Friend) ? "Friend" : request.Friend.Trim(),
                Libraries = chosen,
                Created = now,
                Expires = now.AddDays(Math.Clamp(request.Days, 1, 90)),
            };
            state.Invites.Add(invite);
            return Info(state, invite, libraries);
        });
        return result is null
            ? Conflict("Set the server's internet address first: friends reach it there.")
            : result;
    }

    /// <summary>
    /// Takes an invite back. If the friend joined, their sign-in is removed: the access ends.
    /// </summary>
    /// <param name="code">The invite's code.</param>
    /// <returns>Nothing.</returns>
    [HttpDelete("Invites/{code}")]
    [Authorize(Policy = "RequiresElevation")]
    [ProducesResponseType(StatusCodes.Status204NoContent)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult> DeleteInvite([FromRoute] string code)
    {
        var removed = Store.Update(state =>
        {
            var invite = SharingStore.Find(state, code);
            if (invite is not null)
            {
                state.Invites.Remove(invite);
            }

            return invite;
        });
        if (removed is null)
        {
            return NotFound();
        }

        if (removed.UserId != Guid.Empty && _users.GetUserById(removed.UserId) is not null)
        {
            await _users.DeleteUserAsync(removed.UserId).ConfigureAwait(false);
            _logger.LogInformation("Homeplay sharing: access of {Friend} ended", removed.Friend);
        }

        return NoContent();
    }

    /// <summary>
    /// The page an invite link opens on the friend's phone.
    /// </summary>
    /// <param name="code">The invite's code.</param>
    /// <returns>An HTML page.</returns>
    [HttpGet("Join/{code}")]
    [AllowAnonymous]
    [Produces("text/html")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public ContentResult JoinPageFor([FromRoute] string code)
    {
        var state = Store.Load();
        var invite = SharingStore.Find(state, code);
        var libraries = Libraries();
        var names = invite?.Libraries.Select(id => libraries.FirstOrDefault(l => l.Id == id)?.Name).OfType<string>().ToList() ?? [];
        var server = state.PublicUrl.Length > 0 ? state.PublicUrl : $"{Request.Scheme}://{Request.Host}";
        var folder = System.IO.Path.GetDirectoryName(typeof(ShareController).Assembly.Location) ?? ".";
        var appUrl = PhoneLink.AppUrl(server, PhoneLink.FindApk(folder) is not null);
        var setupUrl = PhoneLink.FindSetup(folder) is null ? null : $"{server.TrimEnd('/')}/Homeplay/Setup";
        var page = JoinPage.Html(SharingStore.StateOf(invite, DateTime.UtcNow), _host.FriendlyName, names, server, invite?.Code ?? code, appUrl, setupUrl);
        return Content(page, "text/html; charset=utf-8");
    }

    /// <summary>
    /// The friend's app uses the invite: a sign-in of their own is made and the phone signed in.
    /// </summary>
    /// <param name="request">The code and the phone.</param>
    /// <returns>The sign-in for the app.</returns>
    [HttpPost("Join")]
    [AllowAnonymous]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    [ProducesResponseType(StatusCodes.Status410Gone)]
    public async Task<ActionResult<JoinResult>> Join([FromBody] JoinRequest request)
    {
        await JoinGate.WaitAsync().ConfigureAwait(false);
        try
        {
            var state = Store.Load();
            var invite = SharingStore.Find(state, request.Code);
            switch (SharingStore.StateOf(invite, DateTime.UtcNow))
            {
                case InviteState.Unknown:
                    return NotFound("There is no such invite.");
                case InviteState.Joined:
                    return StatusCode(StatusCodes.Status410Gone, "This invite has been used already. Ask for a new one.");
                case InviteState.Expired:
                    return StatusCode(StatusCodes.Status410Gone, "This invite has expired. Ask for a new one.");
            }

            var name = SharingStore.UserNameFor(invite!.Friend, n => _users.GetUserByName(n) is not null);
            var password = SharingStore.NewPassword();
            var user = await _users.CreateUserAsync(name).ConfigureAwait(false);
            await _users.ChangePassword(user.Id, password).ConfigureAwait(false);
            var remote = HttpContext.Connection.RemoteIpAddress?.ToString() ?? string.Empty;
            var policy = _users.GetUserDto(user, remote).Policy;
            policy.IsAdministrator = false;
            policy.IsHidden = true;
            policy.EnableAllFolders = false;
            policy.EnabledFolders = [.. invite.Libraries];
            policy.EnableContentDeletion = false;
            policy.EnableContentDeletionFromFolders = [];
            policy.EnableRemoteAccess = true;
            policy.EnableCollectionManagement = false;
            policy.EnableSubtitleManagement = false;
            policy.EnableLyricManagement = false;
            policy.EnableLiveTvManagement = false;
            policy.EnablePublicSharing = false;
            policy.EnableRemoteControlOfOtherUsers = false;
            policy.EnableSharedDeviceControl = false;
            await _users.UpdatePolicyAsync(user.Id, policy).ConfigureAwait(false);

            var session = await _sessions.AuthenticateNewSession(new AuthenticationRequest
            {
                Username = name,
                Password = password,
                App = "Homeplay",
                AppVersion = "1.0",
                DeviceId = string.IsNullOrWhiteSpace(request.DeviceId) ? Guid.NewGuid().ToString("N") : request.DeviceId,
                DeviceName = string.IsNullOrWhiteSpace(request.DeviceName) ? "Phone" : request.DeviceName,
                RemoteEndPoint = remote,
            }).ConfigureAwait(false);

            Store.Update(s =>
            {
                var i = SharingStore.Find(s, invite.Code);
                if (i is not null)
                {
                    i.UserId = user.Id;
                    i.Joined = DateTime.UtcNow;
                }

                return i;
            });
            _logger.LogInformation("Homeplay sharing: {Friend} joined as {User}", invite.Friend, name);
            return new JoinResult(_host.FriendlyName, user.Id, name, session.AccessToken);
        }
        finally
        {
            JoinGate.Release();
        }
    }
}

/// <summary>A library to share.</summary>
/// <param name="Id">Its id.</param>
/// <param name="Name">Its name.</param>
/// <param name="CollectionType">movies, tvshows, music, homevideos...; null for mixed.</param>
public sealed record LibraryInfo(Guid Id, string Name, string? CollectionType);

/// <summary>An invite as the owner sees it.</summary>
/// <param name="Code">The secret code.</param>
/// <param name="Friend">The friend's name.</param>
/// <param name="Libraries">The libraries' ids.</param>
/// <param name="LibraryNames">The libraries' names.</param>
/// <param name="Created">When it was made (UTC).</param>
/// <param name="Expires">Until when the link works (UTC).</param>
/// <param name="Joined">When the friend joined (UTC), if they did.</param>
/// <param name="State">Waiting, Joined or Expired.</param>
/// <param name="Link">The link to send.</param>
public sealed record InviteInfo(string Code, string Friend, IReadOnlyList<Guid> Libraries, IReadOnlyList<string> LibraryNames, DateTime Created, DateTime Expires, DateTime? Joined, string State, string Link);

/// <summary>The owner's sharing.</summary>
/// <param name="PublicUrl">The server's internet address; empty when not set.</param>
/// <param name="Libraries">The libraries there are.</param>
/// <param name="Invites">The invites.</param>
public sealed record SharingInfo(string PublicUrl, IReadOnlyList<LibraryInfo> Libraries, IReadOnlyList<InviteInfo> Invites);

/// <summary>The server's internet address to keep.</summary>
/// <param name="PublicUrl">The address; empty to clear it.</param>
public sealed record SharingRequest(string? PublicUrl);

/// <summary>A new invite.</summary>
/// <param name="Friend">The friend's name.</param>
/// <param name="Libraries">The libraries they see.</param>
/// <param name="Days">How many days the link works if unused (1 to 90).</param>
public sealed record InviteRequest(string? Friend, IReadOnlyList<Guid> Libraries, int Days = 7);

/// <summary>The friend's app using an invite.</summary>
/// <param name="Code">The code from the link.</param>
/// <param name="DeviceId">The app's device id.</param>
/// <param name="DeviceName">The phone's name.</param>
public sealed record JoinRequest(string Code, string? DeviceId, string? DeviceName);

/// <summary>The friend's sign-in.</summary>
/// <param name="ServerName">The server's name.</param>
/// <param name="UserId">The friend's user.</param>
/// <param name="UserName">The friend's user name.</param>
/// <param name="AccessToken">The app's token.</param>
public sealed record JoinResult(string ServerName, Guid UserId, string UserName, string AccessToken);
