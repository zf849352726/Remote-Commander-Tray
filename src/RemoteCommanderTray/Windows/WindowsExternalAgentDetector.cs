using System.Management;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text.RegularExpressions;
using RemoteCommanderTray.Core;

namespace RemoteCommanderTray.Windows;

/// <summary>
/// Checks external Node/npm Remote CLI processes before starting a managed agent.
/// Uses a read-only WMI query; never opens process handles or terminates processes.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class WindowsExternalAgentDetector : IExternalAgentDetector
{
    private static readonly Regex RemoteArgument = new(
        @"(?:^|[\s""'])remote(?=$|[\s""'])",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.Compiled);

    public ExternalAgentCheck Check()
    {
        try
        {
            using var searcher = new ManagementObjectSearcher(
                @"root\CIMV2",
                "SELECT ProcessId, CommandLine FROM Win32_Process " +
                "WHERE Name='node.exe' OR Name='cmd.exe' OR Name='desktop-commander.exe'");
            using var processes = searcher.Get();
            var inspectionIncomplete = false;
            foreach (ManagementObject process in processes)
            {
                using (process)
                {
                    var line = process["CommandLine"] as string;
                    if (string.IsNullOrWhiteSpace(line))
                    {
                        inspectionIncomplete = true;
                        continue;
                    }

                    if (IsRemoteCommandLine(line))
                    {
                        var id = Convert.ToInt32(process["ProcessId"], System.Globalization.CultureInfo.InvariantCulture);
                        return new ExternalAgentCheck(ExternalAgentPresence.Conflict, id);
                    }
                }
            }

            return inspectionIncomplete
                ? new ExternalAgentCheck(ExternalAgentPresence.Unknown)
                : new ExternalAgentCheck(ExternalAgentPresence.None);
        }
        catch (Exception ex) when (ex is ManagementException or UnauthorizedAccessException
            or COMException or InvalidOperationException)
        {
            // If inspection cannot be completed, fail closed rather than risk a duplicate.
            return new ExternalAgentCheck(ExternalAgentPresence.Unknown);
        }
    }

    internal static bool IsRemoteCommandLine(string? commandLine)
    {
        if (string.IsNullOrWhiteSpace(commandLine) || !RemoteArgument.IsMatch(commandLine))
            return false;

        var hasPackage = commandLine.Contains("@wonderwhy-er", StringComparison.OrdinalIgnoreCase)
            && commandLine.Contains("desktop-commander", StringComparison.OrdinalIgnoreCase);
        var hasShim = commandLine.Contains("desktop-commander.cmd", StringComparison.OrdinalIgnoreCase)
            || commandLine.Contains("desktop-commander.exe", StringComparison.OrdinalIgnoreCase);
        return hasPackage || hasShim;
    }
}
