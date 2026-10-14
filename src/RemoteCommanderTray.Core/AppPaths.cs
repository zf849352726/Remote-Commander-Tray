using System.Security.Principal;

namespace RemoteCommanderTray.Core;

/// <summary>
/// Everything the tray writes lives under one per-user folder. Nothing is written
/// outside it, and the official device's own credential store
/// (<c>%USERPROFILE%\.desktop-commander-device</c>) is never read or touched.
/// </summary>
public sealed class AppPaths
{
    public const string FolderName = "RemoteCommanderTray";
    public const string DataBaseDirectory = @"D:\Apps\RemoteCommanderTrayData";

    /// <summary>Separate settings and logs for each signed-in Windows account.</summary>
    public static string DefaultUserDataDirectory()
    {
        if (OperatingSystem.IsWindows())
        {
            var sid = WindowsIdentity.GetCurrent().User?.Value
                ?? throw new InvalidOperationException("Unable to determine Windows user SID.");
            return Path.Combine(DataBaseDirectory, sid);
        }

        return Path.Combine(DataBaseDirectory, Environment.UserName);
    }

    public AppPaths(string? rootOverride = null)
    {
        Root = rootOverride ?? DefaultUserDataDirectory();
        LogDirectory = Path.Combine(Root, "logs");
        SettingsFile = Path.Combine(Root, "settings.json");
        AgentLogFile = Path.Combine(LogDirectory, "agent.log");
        VerboseAgentLogFile = Path.Combine(LogDirectory, "agent-verbose.log");
    }

    /// <summary><c>D:\Apps\RemoteCommanderTrayData\&lt;Windows SID&gt;</c>.</summary>
    public string Root { get; }

    /// <summary>Per-user log folder below the D: data root.</summary>
    public string LogDirectory { get; }

    /// <summary>Per-user settings file below the D: data root.</summary>
    public string SettingsFile { get; }

    /// <summary>Normal per-user log on the D: drive.</summary>
    public string AgentLogFile { get; }

    /// <summary>
    /// Per-user verbose log on the D: drive, written only
    /// when the user opts in. Never read by diagnostics.
    /// </summary>
    public string VerboseAgentLogFile { get; }

    /// <summary>Creates the folders if they are missing.</summary>
    public void EnsureCreated()
    {
        Directory.CreateDirectory(Root);
        Directory.CreateDirectory(LogDirectory);
    }
}
