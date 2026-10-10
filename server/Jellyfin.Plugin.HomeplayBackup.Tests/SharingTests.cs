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
        Assert.Equal("https://pc.ts.net/Homeplay/Join/ABC", SharingStore.JoinLink("https://pc.ts.net/", "ABC"));
    }

    [Fact]
    public void TheJoinPageOpensTheAppOrDownloadsIt()
    {
        var page = JoinPage.Html(InviteState.Waiting, "Anna's <Homeplay>", ["Movies", "Music"], "https://pc.ts.net", "ABC", "https://pc.ts.net/Homeplay/App");
        Assert.Contains("Anna&#39;s &lt;Homeplay&gt;", page, StringComparison.Ordinal);
        Assert.Contains("Movies, Music", page, StringComparison.Ordinal);
        Assert.Contains("intent://join?server=https%3A%2F%2Fpc.ts.net&amp;code=ABC#Intent;scheme=homeplay;package=dev.homeplay.homeplay;S.browser_fallback_url=https%3A%2F%2Fpc.ts.net%2FHomeplay%2FApp;end", page, StringComparison.Ordinal);
        Assert.Contains("homeplay://join?server=https%3A%2F%2Fpc.ts.net&amp;code=ABC", page, StringComparison.Ordinal);
        Assert.Contains("Download Homeplay for Android", page, StringComparison.Ordinal);
        Assert.DoesNotContain("Open in Homeplay", JoinPage.Html(InviteState.Joined, "PC", [], "https://pc.ts.net", "ABC", "x"), StringComparison.Ordinal);
        Assert.Contains("expired", JoinPage.Html(InviteState.Expired, "PC", [], "https://pc.ts.net", "ABC", "x"), StringComparison.Ordinal);
    }

    [Fact]
    public void WithoutAnAppFileTheInviteSendsToGooglePlay()
    {
        Assert.Equal("https://pc.ts.net/Homeplay/App", Phone.PhoneLink.AppUrl("https://pc.ts.net/", true));
        var store = Phone.PhoneLink.AppUrl("https://pc.ts.net", false);
        Assert.Equal(Phone.PhoneLink.PlayStoreUrl, store);
        var page = JoinPage.Html(InviteState.Waiting, "PC", ["Music"], "https://pc.ts.net", "ABC", store);
        Assert.Contains("Get Homeplay on Google Play", page, StringComparison.Ordinal);
        Assert.Contains("opens it in Google Play", page, StringComparison.Ordinal);
        Assert.Contains("S.browser_fallback_url=https%3A%2F%2Fplay.google.com", page, StringComparison.Ordinal);
    }

    [Fact]
    public void TheJoinPageTellsHowToMakeAServerOfOnesOwn()
    {
        var page = JoinPage.Html(InviteState.Waiting, "PC", ["Music"], "https://pc.ts.net", "ABC", "x", "https://pc.ts.net/Homeplay/Setup");
        Assert.Contains("Your own Homeplay", page, StringComparison.Ordinal);
        Assert.Contains("href=\"https://pc.ts.net/Homeplay/Setup\"", page, StringComparison.Ordinal);
        Assert.DoesNotContain("Ask whoever sent you this link for the file", page, StringComparison.Ordinal);

        // A server without the installer next to the plugin: the friend asks for the file.
        var without = JoinPage.Html(InviteState.Expired, "PC", [], "https://pc.ts.net", "ABC", "x");
        Assert.Contains("Your own Homeplay", without, StringComparison.Ordinal);
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
