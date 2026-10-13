using RemoteCommanderTray.Windows;
using Xunit;

namespace RemoteCommanderTray.Windows.Tests;

public sealed class ExternalAgentDetectorTests
{
    [Theory]
    [InlineData("\"node.exe\" \"C:\\node_modules\\npm\\bin\\npx-cli.js\" @wonderwhy-er/desktop-commander@latest remote")]
    [InlineData("\"node\" \"C:\\npm-cache\\_npx\\hash\\node_modules\\@wonderwhy-er\\desktop-commander\\dist\\index.js\" remote")]
    [InlineData("\"cmd.exe\" /d /s /c \"desktop-commander.cmd remote\"")]
    [InlineData("\"desktop-commander.exe\" remote")]
    public void Recognizes_remote_cli_processes(string commandLine)
        => Assert.True(WindowsExternalAgentDetector.IsRemoteCommandLine(commandLine));

    [Theory]
    [InlineData("\"node.exe\" server.js")]
    [InlineData("\"node.exe\" \"C:\\node_modules\\@wonderwhy-er\\desktop-commander\\dist\\index.js\"")]
    [InlineData("\"node.exe\" \"C:\\node_modules\\@wonderwhy-er\\desktop-commander\\dist\\index.js\" mcp")]
    [InlineData("\"node.exe\" \"C:\\foo\\desktop-commander\\dist\\index.js\" remote")]
    [InlineData("\"node.exe\" \"C:\\node_modules\\@wonderwhy-er\\desktop-commander\\dist\\index.js\" --remote")]
    [InlineData("")]
    public void Ignores_unrelated_or_non_remote_processes(string commandLine)
        => Assert.False(WindowsExternalAgentDetector.IsRemoteCommandLine(commandLine));
}
