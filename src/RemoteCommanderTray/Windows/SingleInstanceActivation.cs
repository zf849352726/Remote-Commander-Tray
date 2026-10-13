using System.Runtime.Versioning;

namespace RemoteCommanderTray.Windows;

/// <summary>
/// Small per-session IPC event. A second invocation can unhide the primary tray
/// without launching a second process manager or changing the Remote state.
/// </summary>
[SupportedOSPlatform("windows")]
internal sealed class SingleInstanceActivation : IDisposable
{
    private readonly EventWaitHandle _event;
    private RegisteredWaitHandle? _listener;

    public SingleInstanceActivation(string name)
        => _event = new EventWaitHandle(false, EventResetMode.AutoReset, name);

    public void Listen(Action onActivate)
    {
        if (_listener is not null) throw new InvalidOperationException("Listener already registered.");
        _listener = ThreadPool.RegisterWaitForSingleObject(
            _event, (_, timedOut) =>
            {
                if (!timedOut) onActivate();
            }, null, Timeout.Infinite, executeOnlyOnce: false);
    }

    public static bool TryActivate(string name)
    {
        try
        {
            using var signal = EventWaitHandle.OpenExisting(name);
            return signal.Set();
        }
        catch (WaitHandleCannotBeOpenedException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
    }

    public void Dispose()
    {
        _listener?.Unregister(null);
        _event.Dispose();
    }
}
