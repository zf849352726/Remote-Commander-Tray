using RemoteCommanderTray.Core;
using Xunit;

namespace RemoteCommanderTray.Core.Tests;

public sealed class DefaultDataPathTests
{
    [Fact]
    public void Default_paths_are_on_D_drive_and_are_separated_by_windows_account()
    {
        var paths = new AppPaths();
        Assert.StartsWith(@"D:\Apps\RemoteCommanderTrayData\", paths.Root, StringComparison.OrdinalIgnoreCase);
        Assert.Equal(Path.Combine(paths.Root, "settings.json"), paths.SettingsFile);
        Assert.Equal(Path.Combine(paths.Root, "logs"), paths.LogDirectory);
        Assert.Equal(Path.Combine(paths.LogDirectory, "agent.log"), paths.AgentLogFile);
        Assert.Equal(Path.Combine(paths.LogDirectory, "agent-verbose.log"), paths.VerboseAgentLogFile);
        if (OperatingSystem.IsWindows())
        {
            var sid = System.Security.Principal.WindowsIdentity.GetCurrent().User!.Value;
            Assert.Equal(Path.Combine(AppPaths.DataBaseDirectory, sid), paths.Root);
        }
    }

    [Fact]
    public void Explicit_test_data_root_remains_isolated()
    {
        var isolated = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N"));
        var paths = new AppPaths(isolated);
        Assert.Equal(isolated, paths.Root);
        Assert.Equal(Path.Combine(isolated, "settings.json"), paths.SettingsFile);
    }
}
