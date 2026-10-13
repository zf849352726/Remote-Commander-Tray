using RemoteCommanderTray.Windows;
using Xunit;

namespace RemoteCommanderTray.Windows.Tests;

public sealed class SingleInstanceActivationTests
{
    [Fact]
    public async Task A_second_launch_signals_the_primary_without_creating_another_manager()
    {
        var name = @"Local\RemoteCommanderTray.Test." + Guid.NewGuid().ToString("N");
        using var primary = new SingleInstanceActivation(name);
        var seen = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        primary.Listen(() => seen.TrySetResult());

        Assert.True(SingleInstanceActivation.TryActivate(name));
        await seen.Task.WaitAsync(TimeSpan.FromSeconds(5));
    }

    [Fact]
    public void Missing_primary_is_not_created_by_a_secondary_signal()
    {
        var name = @"Local\RemoteCommanderTray.Missing." + Guid.NewGuid().ToString("N");
        Assert.False(SingleInstanceActivation.TryActivate(name));
    }
}
