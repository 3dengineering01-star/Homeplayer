using MediaBrowser.Model.Plugins;

namespace Jellyfin.Plugin.HomeplayBackup.Configuration;

/// <summary>
/// Plugin settings.
/// </summary>
public class PluginConfiguration : BasePluginConfiguration
{
    /// <summary>
    /// Gets or sets the folder photos go to; empty until the admin sets it, and backups are refused till then.
    /// </summary>
    public string BackupFolder { get; set; } = string.Empty;
}
