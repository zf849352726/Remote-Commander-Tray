using RemoteCommanderTray.Core;
using Xunit;

namespace RemoteCommanderTray.Core.Tests;

public sealed class ExternalAgentStartGuardTests
{
    [Theory]
    [InlineData(ExternalAgentPresence.Conflict)]
    [InlineData(ExternalAgentPresence.Unknown)]
    public async Task Blocks_an_external_or_unverifiable_process_without_starting_anything(
        ExternalAgentPresence presence)
    {
        var folder = Path.Combine(Path.GetTempPath(), "rct-conflict-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        try
        {
            using var log = new RollingFileLog(Path.Combine(folder, "agent.log"), 64 * 1024, 1);
            var factory = new FakeAgentProcessFactory();
            await using var supervisor = new AgentSupervisor(
                new AgentStateMachine(),
                factory,
                new AgentCommandResolver(new InstalledAgentEnvironment()),
                () => new TraySettings(),
                log,
                externalAgentDetector: new StubDetector(presence));

            await supervisor.StartAsync();

            Assert.Equal(0, factory.CreatedCount);
            Assert.False(supervisor.Snapshot.AgentWanted);
            Assert.False(supervisor.IsRunning);
        }
        finally { Directory.Delete(folder, true); }
    }

    private sealed class StubDetector(ExternalAgentPresence presence) : IExternalAgentDetector
    {
        public ExternalAgentCheck Check() => new(presence, 1234);
    }
}
