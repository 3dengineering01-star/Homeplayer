using System;
using System.IO;
using System.Linq;
using Jellyfin.Plugin.HomeplayBackup.Sharing;
using Xunit;

namespace Jellyfin.Plugin.HomeplayBackup.Tests;

public sealed class SharingTests : IDisposable
{
    private static readonly DateTime Now = new(2026, 10, 10, 12, 0, 0, DateTimeKind.Utc);

    private readonly string _folder = Path.Combine(Path.GetTempPath(), "homeplay-sharing-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_folder))
        {
            Directory.Delete(_folder, true);
        }
    }

    [Fact]
    public void InvitesAreKeptInTheirOwnFile()
    {
        var file = Path.Combine(_folder, "sharing.json");
        var store = new SharingStore(file);
        Assert.Empty(store.Load().Invites);
        var library = Guid.NewGuid();
        store.Update(s =>
        {
            s.PublicUrl = "https://pc.tail1234.ts.net";
            s.Invites.Add(new Invite { Code = "ABC", Friend = "Anna", Libraries = [library], Created = Now, Expires = Now.AddDays(7) });
            return 0;
        });
        var again = new SharingStore(file).Load();
        Assert.Equal("https://pc.tail1234.ts.net", again.PublicUrl);
        Assert.Equal(library, again.Invites.Single().Libraries.Single());
        Assert.Same(again.Invites[0], SharingStore.Find(again, " abc "));
        Assert.Null(SharingStore.Find(again, "XYZ"));
    }

    [Fact]
    public void AnInviteWorksOnceAndUntilItExpires()
    {
        var invite = new Invite { Code = "A", Created = Now, Expires = Now.AddDays(7) };
        Assert.Equal(InviteState.Waiting, SharingStore.StateOf(invite, Now.AddDays(6)));
        Assert.Equal(InviteState.Expired, SharingStore.StateOf(invite, Now.AddDays(8)));
        Assert.Equal(InviteState.Unknown, SharingStore.StateOf(null, Now));
        var friend = Guid.NewGuid();
        invite.UserId = friend;
        Assert.Equal(InviteState.Joined, SharingStore.StateOf(invite, Now.AddDays(8)));
        var state = new SharingState { Invites = [invite] };
        Assert.True(SharingStore.IsFriend(state, friend));
        Assert.False(SharingStore.IsFriend(state, Guid.NewGuid()));
        Assert.False(SharingStore.IsFriend(state, Guid.Empty));
    }

    [Fact]
    public void TheOwnerSeesWhenAFriendWasLastSeenAndWhatTheyWatch()
    {
        // Never signed in since joining: nothing to show.
        Assert.Equal(new FriendActivity(null, null), SharingStore.Activity([], null, Now));

        var a = SharingStore.Activity(
            [(Now.AddMinutes(-1), "Dune"), (Now.AddDays(-2), null)],
            Now.AddHours(-3),
            Now);
        Assert.Equal(Now.AddMinutes(-1), a.LastSeen);
        Assert.Equal("Dune", a.Watching);

        // A session quiet for a while plays nothing, even if it still names a movie.
        var quiet = SharingStore.Activity([(Now.AddMinutes(-30), "Dune")], Now.AddHours(-3), Now);
        Assert.Equal(Now.AddMinutes(-30), quiet.LastSeen);
        Assert.Null(quiet.Watching);

        // The user's own activity counts when it is newer than any session.
        Assert.Equal(Now.AddMinutes(-2), SharingStore.Activity([(Now.AddDays(-1), null)], Now.AddMinutes(-2), Now).LastSeen);
    }

    [Fact]
    public void ThePhoneThatJoinedIsKeptShort()
    {
        Assert.Equal("Google Pixel 10a", SharingStore.DeviceName("  Google Pixel 10a "));
        Assert.Equal(string.Empty, SharingStore.DeviceName(null));
        Assert.Equal(60, SharingStore.DeviceName(new string('x', 200)).Length);

        var file = Path.Combine(_folder, "sharing.json");
        var store = new SharingStore(file);
        store.Update(s =>
        {
            s.Invites.Add(new Invite { Code = "A", Friend = "Anna", Created = Now, Expires = Now.AddDays(7), UserId = Guid.NewGuid(), Device = "Google Pixel 10a" });
            return 0;
        });
        Assert.Equal("Google Pixel 10a", new SharingStore(file).Load().Invites.Single().Device);
    }

    [Fact]
    public void CodesAreLongAndReadable()
    {
        var codes = Enumerable.Range(0, 200).Select(_ => SharingStore.NewCode()).ToList();
        Assert.All(codes, c => Assert.Equal(20, c.Length));
        Assert.All(codes, c => Assert.DoesNotMatch("[01OIL]", c));
        Assert.Equal(codes.Count, codes.Distinct().Count());
    }

    [Theory]
    [InlineData("pc.tail1234.ts.net", "https://pc.tail1234.ts.net")]
    [InlineData(" https://pc.tail1234.ts.net/ ", "https://pc.tail1234.ts.net")]
    [InlineData("http://example.com:8096/", "http://example.com:8096")]
    [InlineData("ftp://example.com", null)]
    [InlineData("not an address", null)]
    [InlineData("localhost", null)]
    [InlineData("", null)]
    public void TheInternetAddressIsASiteAddress(string input, string? expected) =>
        Assert.Equal(expected, SharingStore.NormalizeUrl(input));

    [Fact]
    public void FriendsGetPlainUnusedUserNames()
    {
        var taken = new[] { "Anna", "Anna 2" };
        Assert.Equal("Anna 3", SharingStore.UserNameFor(" Anna ", taken.Contains));
        Assert.Equal("Friend", SharingStore.UserNameFor("<>/", _ => false));
        Assert.Equal("Пётр", SharingStore.UserNameFor("Пётр", _ => false));
    }

    [Fact]
    public void TheInviteLinkLeadsToTheWebsiteAndKeepsTheServerAfterTheHash()
    {
        Assert.Equal(
            "https://ownmedia.app/join.html#s=https%3A%2F%2Fpc.ts.net&n=Anna%27s%20%D0%BA%D0%B8%D0%BD%D0%BE&c=ABC",
            SharingStore.JoinLink("https://pc.ts.net/", "Anna's кино", "ABC"));
        Assert.Equal(
            "https://ownmedia.app/join.html#s=http%3A%2F%2F192.168.1.10%3A8096&c=Q7",
            SharingStore.JoinLink("http://192.168.1.10:8096", " ", "Q7"));
    }

    [Fact]
    public void TheJoinPageOpensTheAppOrDownloadsIt()
    {
        var page = JoinPage.Html(InviteState.Waiting, "Anna's <Homeplay>", ["Movies", "Music"], "https://pc.ts.net", "ABC", "https://pc.ts.net/Homeplay/App");
        Assert.Contains("Anna&#39;s &lt;Homeplay&gt;", page, StringComparison.Ordinal);
        Assert.Contains("Movies, Music", page, StringComparison.Ordinal);
        Assert.Contains("intent://join?server=https%3A%2F%2Fpc.ts.net&amp;code=ABC#Intent;scheme=homeplay;package=dev.homeplay.homeplay;S.browser_fallback_url=https%3A%2F%2Fpc.ts.net%2FHomeplay%2FApp;end", page, StringComparison.Ordinal);
        Assert.Contains("homeplay://join?server=https%3A%2F%2Fpc.ts.net&amp;code=ABC", page, StringComparison.Ordinal);
        Assert.Contains("Download OwnMedia for Android", page, StringComparison.Ordinal);
        Assert.Contains("Install anyway", page, StringComparison.Ordinal);
        Assert.DoesNotContain("Open in OwnMedia", JoinPage.Html(InviteState.Joined, "PC", [], "https://pc.ts.net", "ABC", "x"), StringComparison.Ordinal);
        Assert.Contains("expired", JoinPage.Html(InviteState.Expired, "PC", [], "https://pc.ts.net", "ABC", "x"), StringComparison.Ordinal);
    }

    [Fact]
    public void TheInviteGetsTheNewestAppFromTheWebsite()
    {
        Assert.Equal("https://ownmedia.app/download/OwnMedia.apk", Phone.PhoneLink.AppUrl);
        var page = JoinPage.Html(InviteState.Waiting, "PC", ["Music"], "https://pc.ts.net", "ABC", Phone.PhoneLink.AppUrl);
        Assert.Contains("S.browser_fallback_url=https%3A%2F%2Fownmedia.app%2Fdownload%2FOwnMedia.apk", page, StringComparison.Ordinal);
        Assert.Contains("href=\"https://ownmedia.app/download/OwnMedia.apk\"", page, StringComparison.Ordinal);
        Assert.Contains("Download OwnMedia for Android", page, StringComparison.Ordinal);
        Assert.Contains("Install anyway", page, StringComparison.Ordinal);
    }

    [Fact]
    public void AGooglePlayAddressSaysGooglePlay()
    {
        var store = Phone.PhoneLink.PlayStoreUrl;
        var page = JoinPage.Html(InviteState.Waiting, "PC", ["Music"], "https://pc.ts.net", "ABC", store);
        Assert.Contains("Get OwnMedia on Google Play", page, StringComparison.Ordinal);
        Assert.Contains("opens it in Google Play", page, StringComparison.Ordinal);
        Assert.DoesNotContain("Install anyway", page, StringComparison.Ordinal);
        Assert.Contains("S.browser_fallback_url=https%3A%2F%2Fplay.google.com", page, StringComparison.Ordinal);
    }

    // The installer turns on Tailscale Funnel and leaves the address: the owner does not type it.
    [Fact]
    public void TheInstallersAddressIsTakenOnceWhenThereIsNone()
    {
        var state = new SharingState();
        Assert.False(SharingStore.TakeSuggestion(state, null));
        Assert.False(SharingStore.TakeSuggestion(state, "not an address"));
        Assert.True(SharingStore.TakeSuggestion(state, "https://pc.tail1234.ts.net/\r\n"));
        Assert.Equal("https://pc.tail1234.ts.net", state.PublicUrl);

        // Cleared by the owner on purpose: the same address is not put back.
        state.PublicUrl = string.Empty;
        Assert.False(SharingStore.TakeSuggestion(state, "https://pc.tail1234.ts.net"));

        // An address the owner typed stays.
        state.PublicUrl = "https://music.example.com";
        Assert.False(SharingStore.TakeSuggestion(state, "https://other.tail1234.ts.net"));
        Assert.Equal("https://music.example.com", state.PublicUrl);
    }

    [Fact]
    public void TheJoinPageTellsHowToMakeAServerOfOnesOwn()
    {
        var page = JoinPage.Html(InviteState.Waiting, "PC", ["Music"], "https://pc.ts.net", "ABC", "x", "https://pc.ts.net/Homeplay/Setup");
        Assert.Contains("Your own OwnMedia", page, StringComparison.Ordinal);
        Assert.Contains("href=\"https://pc.ts.net/Homeplay/Setup\"", page, StringComparison.Ordinal);
        Assert.DoesNotContain("Ask whoever sent you this link for the file", page, StringComparison.Ordinal);

        // A server without the installer next to the plugin: the friend asks for the file.
        var without = JoinPage.Html(InviteState.Expired, "PC", [], "https://pc.ts.net", "ABC", "x");
        Assert.Contains("Your own OwnMedia", without, StringComparison.Ordinal);
        Assert.Contains("Ask whoever sent you this link for the file", without, StringComparison.Ordinal);
        Assert.DoesNotContain("/Homeplay/Setup", without, StringComparison.Ordinal);
    }
}

public sealed class SharingAccessTests
{
    // Only the server's owner (an administrator) shares it: a friend's sign-in is not one, so a
    // friend cannot pass the server on.
    [Theory]
    [InlineData(nameof(Api.ShareController.GetSharing))]
    [InlineData(nameof(Api.ShareController.SetSharing))]
    [InlineData(nameof(Api.ShareController.CreateInvite))]
    [InlineData(nameof(Api.ShareController.DeleteInvite))]
    public void OnlyTheOwnerManagesSharing(string method)
    {
        var attribute = typeof(Api.ShareController).GetMethod(method)!
            .GetCustomAttributes(typeof(Microsoft.AspNetCore.Authorization.AuthorizeAttribute), false)
            .Cast<Microsoft.AspNetCore.Authorization.AuthorizeAttribute>()
            .Single();
        Assert.Equal("RequiresElevation", attribute.Policy);
    }
}
