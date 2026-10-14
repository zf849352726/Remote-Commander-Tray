using System.Runtime.Versioning;
using RemoteCommanderTray.Core;
using RemoteCommanderTray.Windows;

namespace RemoteCommanderTray.UI;

/// <summary>
/// The whole user interface: one notify icon and one context menu, with no main window.
/// </summary>
/// <remarks>
/// This class only renders <see cref="AgentSnapshot"/> and turns clicks into supervisor
/// calls. It contains no log parsing and no state rules, which is what keeps the state
/// machine testable without a message loop.
/// </remarks>
[SupportedOSPlatform("windows")]
internal sealed class TrayApplicationContext : ApplicationContext
{
    private const int TooltipMaxLength = 63;
    private readonly System.Windows.Forms.Timer _menuTimer = new() { Interval = 1000 };
    private readonly System.Windows.Forms.Timer _logMaintenanceTimer = new()
        { Interval = 15 * 60 * 1000 };

    private readonly AppPaths _paths;
    private readonly RollingFileLog _log;
    private readonly RollingFileLog? _verboseLog;
    private readonly AgentSupervisor _supervisor;
    private readonly WindowsAgentProcessFactory _processFactory;
    private readonly TrayIcons _icons = new();
    private readonly NotifyIcon _notifyIcon;
    private readonly ContextMenuStrip _menu;
    private readonly Control _marshal;
    private readonly string _version;
    private readonly Func<TraySettings> _settings;

    private readonly ToolStripMenuItem _headerItem;
    private readonly ToolStripMenuItem _detailItem;
    private readonly ToolStripMenuItem _processItem;
    private readonly ToolStripSeparator _signInSeparator;
    private readonly ToolStripMenuItem _openSignInItem;
    private readonly ToolStripMenuItem _copyCodeItem;
    private readonly ToolStripMenuItem _restartItem;
    private readonly ToolStripMenuItem _reauthenticateItem;
    private readonly ToolStripMenuItem _toggleAgentItem;
    private readonly ToolStripMenuItem _remoteAtSignInItem;
    private readonly ToolStripMenuItem _trayStartupItem;
    private readonly ToolStripMenuItem _hideTrayItem;
    private readonly ToolStripMenuItem _verboseLogInfoItem;
    private readonly SettingsStore _settingsStore;

    private AgentSnapshot _snapshot = AgentSnapshot.Initial;
    private bool _busy;
    private bool _exiting;
    private Task? _supervisorDisposeTask;
    private bool _supervisorDisposeFailureReported;

    public TrayApplicationContext(
        AppPaths paths,
        TraySettings settings,
        RollingFileLog log,
        string version,
        IExternalAgentDetector? externalAgentDetector = null)
    {
        _paths = paths;
        _log = log;
        _version = version;
        _settings = () => settings;
        _settingsStore = new SettingsStore(paths.SettingsFile);

        // A real control gives a dependable BeginInvoke target for supervisor callbacks,
        // which arrive on thread-pool threads.
        _marshal = new Control();
        _marshal.CreateControl();

        _processFactory = new WindowsAgentProcessFactory();

        // Raw agent output can contain whatever a remote tool call read, so it only gets
        // written when the user opts in, and is never copied into diagnostics.
        _verboseLog = settings.VerboseAgentLog
            ? new RollingFileLog(paths.VerboseAgentLogFile, settings.VerboseLogMaxBytes, settings.VerboseLogRetainedFiles)
            : null;

        _log.Maintain();
        _logMaintenanceTimer.Tick += (_, _) =>
        {
            _log.Maintain();
            _verboseLog?.Maintain();
        };
        _logMaintenanceTimer.Start();

        var machine = new AgentStateMachine();
        _supervisor = new AgentSupervisor(
            machine,
            _processFactory,
            new AgentCommandResolver(),
            _settings,
            _log,
            verboseLog: _verboseLog,
            externalAgentDetector: externalAgentDetector ?? new WindowsExternalAgentDetector());

        _headerItem = new ToolStripMenuItem("Starting...") { Enabled = false };
        _processItem = new ToolStripMenuItem("Process: Stopped | Connection: Stopped") { Enabled = false };
        _detailItem = new ToolStripMenuItem("Last connected: never") { Enabled = false };
        _signInSeparator = new ToolStripSeparator { Visible = false };
        _openSignInItem = new ToolStripMenuItem("Open sign-in page", null, (_, _) => OpenSignInPage())
        {
            Visible = false,
        };
        _copyCodeItem = new ToolStripMenuItem("Copy sign-in code", null, (_, _) => CopySignInCode())
        {
            Visible = false,
        };
        _restartItem = new ToolStripMenuItem("Restart connection", null, (_, _) => Run(_supervisor.RestartAsync));
        _reauthenticateItem = new ToolStripMenuItem("Re-authenticate...", null, (_, _) => Reauthenticate());
        _toggleAgentItem = new ToolStripMenuItem("Stop agent", null, (_, _) => ToggleAgent());
        _remoteAtSignInItem = new ToolStripMenuItem(
            "Start Remote at sign-in", null, (_, _) => ToggleRemoteAtSignIn())
        {
            CheckOnClick = false,
        };
        _trayStartupItem = new ToolStripMenuItem(
            "Tray startup status", null, (_, _) => OpenStartupSettings());
        _hideTrayItem = new ToolStripMenuItem("Hide tray", null, (_, _) => HideTray());
        _verboseLogInfoItem = new ToolStripMenuItem(
            "Verbose logging ON: sensitive data may be saved")
        { Enabled = false, Visible = settings.VerboseAgentLog };

        _menu = new ContextMenuStrip();
        _menu.Items.AddRange(
        [
            _headerItem,
            _processItem,
            _detailItem,
            _signInSeparator,
            _openSignInItem,
            _copyCodeItem,
            new ToolStripSeparator(),
            _restartItem,
            _reauthenticateItem,
            _toggleAgentItem,
            new ToolStripSeparator(),
            new ToolStripMenuItem("Open Remote MCP", null, (_, _) => Shell.OpenUrl(_settings().RemoteMcpUrl)),
            new ToolStripMenuItem("Open logs", null, (_, _) => OpenLogs()),
            new ToolStripMenuItem("Copy diagnostics", null, (_, _) => CopyDiagnostics()),
            _verboseLogInfoItem,
            new ToolStripSeparator(),
            _remoteAtSignInItem,
            _trayStartupItem,
            _hideTrayItem,
            new ToolStripMenuItem("About", null, (_, _) => ShowAbout()),
            new ToolStripMenuItem("Exit Application", null, (_, _) => ExitApplication()),
        ]);
        _menu.Opening += (_, _) => { RefreshMenu(); _menuTimer.Start(); };
        _menu.Closed += (_, _) => _menuTimer.Stop();
        _menuTimer.Tick += (_, _) => RefreshMenu();

        _notifyIcon = new NotifyIcon
        {
            Icon = _icons.Get(AgentState.Stopped),
            Text = "Remote Commander",
            ContextMenuStrip = _menu,
            Visible = true,
        };
        _notifyIcon.BalloonTipClicked += (_, _) => OnBalloonClicked();
        _notifyIcon.MouseClick += (_, e) =>
        {
            if (e.Button == MouseButtons.Left)
            {
                ShowStatusBalloon();
            }
        };

        _supervisor.Changed += (_, snapshot) => OnUiThread(() => ApplySnapshot(snapshot));
        _supervisor.Notification += (_, notification) => OnUiThread(() => ShowNotification(notification));

        // WinForms has a message pump; SystemEvents forwards actual Windows
        // suspend/resume and user session notifications. Never force-restart the CLI.
        Microsoft.Win32.SystemEvents.PowerModeChanged += OnPowerModeChanged;
        Microsoft.Win32.SystemEvents.SessionSwitch += OnSessionSwitch;

        ApplySnapshot(_supervisor.Snapshot);
        if (settings.VerboseAgentLog)
        {
            _notifyIcon.ShowBalloonTip(
                8_000, "Remote Commander - verbose log enabled",
                "Verbose logs may contain tool arguments, file data or sign-in information. Turn off verboseAgentLog in settings.json when not needed.",
                ToolTipIcon.Warning);
        }
        Run(_supervisor.InitializeAsync);
    }

    // --- rendering -------------------------------------------------------

    private void ApplySnapshot(AgentSnapshot snapshot)
    {
        _snapshot = snapshot;
        _notifyIcon.Icon = _icons.Get(snapshot.State);
        _notifyIcon.Text = BuildTooltip(snapshot);
        RefreshMenu();
    }

    private void RefreshMenu()
    {
        var snapshot = _snapshot;

        _headerItem.Text = $"{GlyphFor(snapshot.State)} {snapshot.StateLabel}{DeviceSuffix(snapshot)}";
        _processItem.Text = $"Process: {(snapshot.ProcessRunning ? "Running" : "Stopped")} | Connection: {snapshot.StateLabel}";
        _detailItem.Text = BuildDetailLine(snapshot);

        var signInVisible = snapshot.State == AgentState.AuthenticationRequired;
        _signInSeparator.Visible = signInVisible;
        _openSignInItem.Visible = signInVisible;
        _openSignInItem.Enabled = !_busy && (snapshot.RequiresReauthentication || !string.IsNullOrWhiteSpace(snapshot.VerificationUri));
        _openSignInItem.Text = snapshot.RequiresReauthentication ? "Sign in again..." : "Open sign-in page";
        _copyCodeItem.Visible = signInVisible && !string.IsNullOrWhiteSpace(snapshot.UserCode);
        _copyCodeItem.Text = snapshot.UserCode is null
            ? "Copy sign-in code"
            : $"Copy code: {snapshot.UserCode}";

        _toggleAgentItem.Text = snapshot.AgentWanted ? "Stop agent" : "Start agent";
        _restartItem.Enabled = !_busy;
        _reauthenticateItem.Enabled = !_busy;
        _toggleAgentItem.Enabled = !_busy;
        RefreshStartupItem();
    }

    /// <summary>Remote autostart and tray registration are separate controls.</summary>
    private void RefreshStartupItem()
    {
        _remoteAtSignInItem.Checked = _settings().StartAgentOnLaunch;
        var state = StartupRegistration.GetState();
        _trayStartupItem.Text = state switch
        {
            StartupState.Enabled => "Tray login startup: enabled (Windows settings)",
            StartupState.DisabledByWindows => "Tray login startup: disabled by Windows",
            StartupState.NotRegistered => "Tray login startup: not registered",
            _ => "Tray login startup: unknown",
        };
    }

    private static string GlyphFor(AgentState state) => state switch
    {
        AgentState.Online => "✓",                 // check
        AgentState.Connecting or AgentState.Starting => "…", // ellipsis
        AgentState.Unknown => "?", // connection needs re-verification
        AgentState.AuthenticationRequired => "\U0001F511", // key
        AgentState.Error => "×",                  // multiplication sign
        _ => "⏸",                                 // pause
    };

    private static string DeviceSuffix(AgentSnapshot snapshot)
        => string.IsNullOrWhiteSpace(snapshot.DeviceName) ? string.Empty : $" - {snapshot.DeviceName}";

    private string BuildDetailLine(AgentSnapshot snapshot)
    {
        if (snapshot.NextRestartUtc is { } due)
        {
            var seconds = Math.Max(0, (int)(due - DateTimeOffset.UtcNow).TotalSeconds);
            return $"Retrying in {seconds}s (attempt {snapshot.RestartCount})";
        }

        if (snapshot.State is AgentState.Error or AgentState.AuthenticationRequired && !string.IsNullOrWhiteSpace(snapshot.LastError))
        {
            return Truncate(snapshot.LastError, 60);
        }

        return snapshot.LastConnectedUtc is { } connected
            ? $"Last connected: {connected.ToLocalTime():HH:mm}"
            : "Last connected: never";
    }

    private static string BuildTooltip(AgentSnapshot snapshot)
    {
        // NotifyIcon.Text refuses anything longer than 63 characters.
        var full = $"Remote Commander - {snapshot.StateLabel}{DeviceSuffix(snapshot)}";
        return full.Length <= TooltipMaxLength
            ? full
            : Truncate(full, TooltipMaxLength);
    }

    private static string Truncate(string value, int maxLength)
        => value.Length <= maxLength ? value : value[..(maxLength - 1)] + "…";

    // --- Windows state events -------------------------------------------

    private void OnPowerModeChanged(object? sender, Microsoft.Win32.PowerModeChangedEventArgs e)
    {
        if (e.Mode == Microsoft.Win32.PowerModes.Resume)
            OnUiThread(_supervisor.OnSystemResumed);
    }

    private void OnSessionSwitch(object? sender, Microsoft.Win32.SessionSwitchEventArgs e)
    {
        if (e.Reason == Microsoft.Win32.SessionSwitchReason.SessionUnlock)
            OnUiThread(_supervisor.OnSystemResumed);
        // Locking does not stop the CLI or force a disconnect.
    }

    // --- commands --------------------------------------------------------

    private void ToggleAgent()
    {
        if (_snapshot.AgentWanted)
        {
            Run(_supervisor.StopAsync);
        }
        else
        {
            Run(_supervisor.StartAsync);
        }
    }

    private void Reauthenticate()
    {
        var answer = MessageBox.Show(
            "Sign out of Desktop Commander on this device and sign in again?\n\n"
            + "The official Desktop Commander CLI clears its own saved credentials and "
            + "opens your browser. Remote Commander Tray never reads or stores them.",
            "Re-authenticate",
            MessageBoxButtons.OKCancel,
            MessageBoxIcon.Question,
            MessageBoxDefaultButton.Button1);

        if (answer == DialogResult.OK)
        {
            Run(_supervisor.ReauthenticateAsync);
        }
    }

    private void OpenSignInPage()
    {
        if (_snapshot.RequiresReauthentication) { Reauthenticate(); return; }
        if (!Shell.OpenUrl(_snapshot.VerificationUri))
        {
            MessageBox.Show(
                "No sign-in page has been reported yet. Open logs to see what the agent is doing.",
                "Remote Commander Tray",
                MessageBoxButtons.OK,
                MessageBoxIcon.Information);
        }
    }

    private void CopySignInCode() => CopyToClipboard(_snapshot.UserCode, "Sign-in code copied.");

    private void OpenLogs()
    {
        if (!Shell.OpenFile(_log.Path) && !Shell.RevealInExplorer(_paths.LogDirectory))
        {
            MessageBox.Show(
                $"Could not open the log folder:\n{_paths.LogDirectory}",
                "Remote Commander Tray",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
        }
    }

    private void CopyDiagnostics()
    {
        var context = new DiagnosticsContext(
            _version,
            Environment.OSVersion.VersionString,
            System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(),
            _supervisor.LaunchDescription,
            _log.Path,
            StartupRegistration.GetState());

        var report = DiagnosticsReport.Build(_snapshot, context);
        CopyToClipboard(report, "Diagnostics copied to the clipboard.");
    }

    private void ToggleRemoteAtSignIn()
    {
        var settings = _settings();
        var previous = settings.StartAgentOnLaunch;
        settings.StartAgentOnLaunch = !previous;
        if (_settingsStore.TrySave(settings, out var error))
        {
            _log.Write(LogSource.Tray,
                $"Remote autostart updated: {settings.StartAgentOnLaunch}.");
            RefreshStartupItem();
            return;
        }

        settings.StartAgentOnLaunch = previous;
        RefreshStartupItem();
        _log.Write(LogSource.Tray, "Unable to save Remote autostart preference.");
        MessageBox.Show(
            $"Could not save Remote autostart preference:\n{error}",
            "Remote Commander Tray",
            MessageBoxButtons.OK,
            MessageBoxIcon.Warning);
    }

    /// <summary>Hides the icon without disposing the manager or touching the Remote.</summary>
    private void HideTray()
    {
        if (_exiting) return;
        _menu.Close();
        _notifyIcon.Visible = false;
    }

    /// <summary>Called from per-session activation IPC or a local UI event.</summary>
    public void ShowTray() => OnUiThread(() =>
    {
        if (_exiting) return;
        _notifyIcon.Visible = true;
        RefreshMenu();
    });

    private static void OpenStartupSettings()
    {
        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(
                StartupRegistration.StartupAppsSettingsUri)
            {
                UseShellExecute = true,
            })?.Dispose();
        }
        catch (Exception ex) when (ex is System.ComponentModel.Win32Exception or InvalidOperationException or IOException)
        {
            // The Settings app is unavailable; the message box already said what to do.
        }
    }

    private void ShowAbout()
    {
        // The dialog gets its own copy: the cached tray icons outlive it.
        using var icon = (Icon)_icons.Get(_snapshot.State).Clone();
        using var about = new AboutForm(_version, icon, _paths.Root);
        about.ShowDialog();
    }

    private void ExitApplication()
    {
        if (_exiting)
        {
            return;
        }

        _exiting = true;
        _notifyIcon.Visible = false;
        _log.Write(LogSource.Tray, "Exit requested; stopping agent.");

        _ = ShutdownAsync();
    }

    private async Task ShutdownAsync()
    {
        try
        {
            await GetSupervisorDisposeTask().ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            _supervisorDisposeFailureReported = true;
            _log.Write(LogSource.Tray, $"Error during shutdown ({ex.GetType().Name}).");
        }

        _log.Write(LogSource.Tray, "Tray exited.");
        OnUiThread(ExitThread);
    }

    // --- notifications ---------------------------------------------------

    private void ShowNotification(TrayNotification notification)
    {
        var icon = notification.Kind switch
        {
            NotificationKind.AuthenticationRequired => ToolTipIcon.Warning,
            NotificationKind.ReauthenticationStarted => ToolTipIcon.Info,
            _ => ToolTipIcon.Error,
        };

        _notifyIcon.ShowBalloonTip(10_000, notification.Title, notification.Message, icon);
    }

    private void ShowStatusBalloon()
    {

        _notifyIcon.ShowBalloonTip(
            5_000,
            $"Remote Commander - {_snapshot.StateLabel}",
            BuildDetailLine(_snapshot),
            ToolTipIcon.None);
    }

    private void OnBalloonClicked()
    {
        // The auth notification may have preceded the CLI's URL line. Always use
        // the current generation's live prompt, never a stale completed sign-in URL.
        var uri = _snapshot.State == AgentState.AuthenticationRequired ? _snapshot.VerificationUri : null;
        if (!Shell.OpenUrl(uri))
        {
            if (_snapshot.State == AgentState.AuthenticationRequired) Reauthenticate();
            else Shell.OpenFile(_log.Path);
        }
    }

    // --- plumbing --------------------------------------------------------

    private void Run(Func<Task> command)
    {
        if (_busy || _exiting) return;
        _busy = true;
        RefreshMenu();
        _ = RunCoreAsync(command);
    }

    private async Task RunCoreAsync(Func<Task> command)
    {
        try
        {
            await command().ConfigureAwait(true);
        }
        catch (Exception ex)
        {
            _log.Write(LogSource.Tray, $"Command failed ({ex.GetType().Name}, HRESULT={ex.HResult:X8}).");
            OnUiThread(() => MessageBox.Show(
                $"That did not work:\n{ex.Message}",
                "Remote Commander Tray",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning));
        }
        finally
        {
            OnUiThread(() =>
            {
                _busy = false;
                RefreshMenu();
            });
        }
    }

    private void CopyToClipboard(string? value, string successMessage)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return;
        }

        try
        {
            Clipboard.SetText(value);
            _notifyIcon.ShowBalloonTip(3_000, "Remote Commander Tray", successMessage, ToolTipIcon.None);
        }
        catch (Exception ex) when (ex is System.Runtime.InteropServices.ExternalException or ThreadStateException)
        {
            _log.Write(LogSource.Tray, $"Clipboard unavailable ({ex.GetType().Name}).");
            MessageBox.Show(
                "Windows would not let the clipboard be written just now. Try again.",
                "Remote Commander Tray",
                MessageBoxButtons.OK,
                MessageBoxIcon.Warning);
        }
    }

    private void OnUiThread(Action action)
    {
        if (_marshal.IsDisposed)
        {
            return;
        }

        try
        {
            if (_marshal.InvokeRequired)
            {
                _marshal.BeginInvoke(action);
            }
            else
            {
                action();
            }
        }
        catch (Exception ex) when (ex is ObjectDisposedException or InvalidOperationException)
        {
            // The message loop is gone; nothing left to render.
        }
    }

    private Task GetSupervisorDisposeTask()
        => _supervisorDisposeTask ??= _supervisor.DisposeAsync().AsTask();

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            Microsoft.Win32.SystemEvents.PowerModeChanged -= OnPowerModeChanged;
            Microsoft.Win32.SystemEvents.SessionSwitch -= OnSessionSwitch;
            _logMaintenanceTimer.Stop();
            _logMaintenanceTimer.Dispose();
            _menuTimer.Dispose();
            try
            {
                GetSupervisorDisposeTask().GetAwaiter().GetResult();
            }
            catch (Exception ex)
            {
                // ExitApplication already reports this failure from ShutdownAsync. A
                // cached faulted disposal task must never escape ApplicationContext.Dispose
                // and get mislabeled by Program.Main as a startup failure.
                if (!_supervisorDisposeFailureReported)
                {
                    _supervisorDisposeFailureReported = true;
                    _log.Write(LogSource.Tray, $"Error during shutdown disposal ({ex.GetType().Name}).");
                }
            }

            _notifyIcon.Visible = false;
            _notifyIcon.Dispose();
            _verboseLog?.Dispose();
            _menu.Dispose();
            _icons.Dispose();
            _marshal.Dispose();
            _log.Dispose();
        }

        base.Dispose(disposing);
    }
}
