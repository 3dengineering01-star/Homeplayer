using System;
using System.IO;
using System.Net;
using Jellyfin.Plugin.HomeplayBackup.Phone;
using QRCoder;
using Xunit;

namespace Jellyfin.Plugin.HomeplayBackup.Tests;

public sealed class PhoneLinkTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "homeplay-phone-" + Guid.NewGuid().ToString("N"));

    public void Dispose()
    {
        if (Directory.Exists(_folder))
        {
            Directory.Delete(_folder, true);
        }
    }

    private static (IPAddress, bool) A(string ip, bool gateway = true) => (IPAddress.Parse(ip), gateway);

    [Fact]
    public void TheHomeNetworkAddressGoesInTheCode()
    {
        Assert.Equal("192.168.1.108", PhoneLink.PickLanAddress([A("127.0.0.1"), A("10.0.0.5"), A("192.168.1.108")])?.ToString());
        Assert.Equal("10.0.0.5", PhoneLink.PickLanAddress([A("100.101.102.103"), A("169.254.3.4"), A("10.0.0.5")])?.ToString());
        Assert.Equal("172.20.1.2", PhoneLink.PickLanAddress([A("172.20.1.2"), A("172.32.0.1"), A("fe80::1")])?.ToString());
        // A virtual machine's adapter has no router: the real network wins even with a lesser kind of address.
        Assert.Equal("10.0.0.5", PhoneLink.PickLanAddress([A("192.168.56.1", gateway: false), A("10.0.0.5")])?.ToString());
        Assert.Null(PhoneLink.PickLanAddress([A("127.0.0.1"), A("100.64.0.1"), A("::1")]));
    }

    [Fact]
    public void OnlyThisComputerItselfIsLoopback()
    {
        Assert.True(PhoneLink.IsLoopback("localhost"));
        Assert.True(PhoneLink.IsLoopback("127.0.0.1"));
        Assert.True(PhoneLink.IsLoopback("[::1]"));
        Assert.False(PhoneLink.IsLoopback("192.168.1.108"));
        Assert.False(PhoneLink.IsLoopback("goodman"));
        Assert.Equal("http://192.168.1.108:8096", PhoneLink.ServerUrl("192.168.1.108", 8096));
    }

    [Fact]
    public void TheAppFileIsFoundNextToThePlugin()
    {
        Assert.Null(PhoneLink.FindApk(_folder));
        Directory.CreateDirectory(_folder);
        Assert.Null(PhoneLink.FindApk(_folder));
        File.WriteAllText(Path.Combine(_folder, "Homeplay-0.2.0.apk"), "x");
        Assert.EndsWith("Homeplay-0.2.0.apk", PhoneLink.FindApk(_folder), StringComparison.Ordinal);
        File.WriteAllText(Path.Combine(_folder, "Homeplay.apk"), "x");
        Assert.EndsWith(PhoneLink.ApkName, PhoneLink.FindApk(_folder), StringComparison.Ordinal);
    }

    [Fact]
    public void ThePageShowsTheCodeTheServerAndNoMarkupFromTheName()
    {
        var png = PngByteQRCodeHelper.GetQRCode("http://192.168.1.108:8096/Homeplay/App", QRCodeGenerator.ECCLevel.M, 10);
        Assert.Equal(new byte[] { 0x89, 0x50, 0x4E, 0x47 }, png[..4]);
        var page = PhoneLink.Page("Anna's <PC>", "http://192.168.1.108:8096", png);
        Assert.Contains("data:image/png;base64,", page, StringComparison.Ordinal);
        Assert.Contains("Anna&#39;s &lt;PC&gt;", page, StringComparison.Ordinal);
        Assert.Contains("http://192.168.1.108:8096", page, StringComparison.Ordinal);
        Assert.DoesNotContain("<PC>", page, StringComparison.Ordinal);
        Assert.Contains("Google Play", PhoneLink.Page("PC", "http://x:8096", null), StringComparison.Ordinal);
    }
}
