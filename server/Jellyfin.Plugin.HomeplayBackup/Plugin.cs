using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using Jellyfin.Plugin.HomeplayBackup.Configuration;
using Jellyfin.Plugin.HomeplayBackup.Sharing;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.HomeplayBackup;

/// <summary>
/// Receives photos and videos from the Homeplay app and keeps them in a folder on the server.
/// </summary>
public class Plugin : BasePlugin<PluginConfiguration>, IHasWebPages
{
    /// <summary>
    /// Initializes a new instance of the <see cref="Plugin"/> class.
    /// </summary>
    /// <param name="applicationPaths">Instance of the <see cref="IApplicationPaths"/> interface.</param>
    /// <param name="xmlSerializer">Instance of the <see cref="IXmlSerializer"/> interface.</param>
    public Plugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : base(applicationPaths, xmlSerializer)
    {
        Instance = this;
    }

    /// <inheritdoc />
    public override string Name => "Homeplay Backup";

    /// <inheritdoc />
    public override Guid Id => Guid.Parse("ca1d038a-d3f7-4ef4-9839-1e93a8105618");

    /// <inheritdoc />
    public override string Description => "Backs up photos and videos from the Homeplay app to a folder on this server.";

    /// <summary>
    /// Gets the current plugin instance.
    /// </summary>
    public static Plugin? Instance { get; private set; }

    /// <summary>
    /// Gets the owner's sharing with friends: the internet address and the invites.
    /// </summary>
    public SharingStore Sharing => new(Path.Combine(DataFolderPath, "sharing.json"));

    /// <inheritdoc />
    public IEnumerable<PluginPageInfo> GetPages()
    {
        return
        [
            new PluginPageInfo
            {
                Name = Name,
                EmbeddedResourcePath = string.Format(CultureInfo.InvariantCulture, "{0}.Configuration.configPage.html", GetType().Namespace)
            }
        ];
    }
}
