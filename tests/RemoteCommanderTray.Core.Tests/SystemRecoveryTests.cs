using RemoteCommanderTray.Core;
using Xunit;

namespace RemoteCommanderTray.Core.Tests;

public sealed class SystemRecoveryTests
{
    [Fact]
    public void Resume_invalidates_only_a_previous_online_state()
    {
        var machine = new AgentStateMachine();
        machine.OnProcessStarted();
        machine.Apply(new AgentSignal(AgentSignalKind.DeviceReady));
        var lastConnected = machine.Snapshot.LastConnectedUtc;

        machine.OnSystemResumed();

        Assert.Equal(AgentState.Unknown, machine.Snapshot.State);
        Assert.Equal("Unknown", machine.Snapshot.StateLabel);
        Assert.True(machine.Snapshot.ProcessRunning);
        Assert.Equal(lastConnected, machine.Snapshot.LastConnectedUtc);
        Assert.Null(machine.Snapshot.NextRestartUtc);
    }

    [Fact]
    public void A_channel_subscription_after_resume_does_not_claim_online_early()
    {
        var machine = new AgentStateMachine();
        machine.OnProcessStarted();
        machine.Apply(new AgentSignal(AgentSignalKind.DeviceReady));
        machine.OnSystemResumed();

        machine.Apply(new AgentSignal(AgentSignalKind.ChannelSubscribed));
        Assert.Equal(AgentState.Unknown, machine.Snapshot.State);

        machine.Apply(new AgentSignal(AgentSignalKind.DeviceOnline));
        Assert.Equal(AgentState.Online, machine.Snapshot.State);
    }

    [Fact]
    public void A_connection_disruption_after_resume_uses_official_reconnect_without_restarting()
    {
        var machine = new AgentStateMachine();
        machine.OnProcessStarted();
        machine.Apply(new AgentSignal(AgentSignalKind.DeviceReady));
        machine.OnSystemResumed();

        machine.Apply(new AgentSignal(AgentSignalKind.ChannelDisrupted, "Channel closed"));

        Assert.Equal(AgentState.Connecting, machine.Snapshot.State);
        Assert.True(machine.Snapshot.ProcessRunning);
        Assert.Equal("Reconnecting", machine.Snapshot.StateLabel);
    }

    [Fact]
    public void Resume_does_not_change_stopped_or_authentication_required()
    {
        var stopped = new AgentStateMachine();
        stopped.OnSystemResumed();
        Assert.Equal(AgentState.Stopped, stopped.Snapshot.State);

        var auth = new AgentStateMachine();
        auth.OnProcessStarted();
        auth.Apply(new AgentSignal(AgentSignalKind.AuthenticationStarted));
        auth.OnSystemResumed();
        Assert.Equal(AgentState.AuthenticationRequired, auth.Snapshot.State);
    }

    [Fact]
    public async Task Supervisor_resume_does_not_spawn_another_agent_or_perform_logout()
    {
        var folder = Path.Combine(Path.GetTempPath(), "rct-resume-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(folder);
        try
        {
            using var log = new RollingFileLog(Path.Combine(folder, "agent.log"), 64 * 1024, 1);
            var factory = new FakeAgentProcessFactory();
            await using var supervisor = new AgentSupervisor(
                new AgentStateMachine(), factory,
                new AgentCommandResolver(new InstalledAgentEnvironment()),
                () => new TraySettings(), log);
            await supervisor.StartAsync();
            var agent = factory.Latest;
            agent.Emit("Device ready:");
            Assert.Equal(AgentState.Online, supervisor.Snapshot.State);

            supervisor.OnSystemResumed();
            supervisor.OnSystemResumed();
            Assert.Equal(AgentState.Unknown, supervisor.Snapshot.State);
            Assert.True(supervisor.Snapshot.ProcessRunning);
            Assert.Equal(1, factory.CreatedCount);
            Assert.Empty(factory.OneShotCommands);
            Assert.False(agent.StopRequested);

            agent.Emit("Device marked as online");
            Assert.Equal(AgentState.Online, supervisor.Snapshot.State);

            await supervisor.StopAsync();
            supervisor.OnSystemResumed();
            Assert.Equal(AgentState.Stopped, supervisor.Snapshot.State);
        }
        finally { Directory.Delete(folder, true); }
    }
}
