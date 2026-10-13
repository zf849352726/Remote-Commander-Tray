namespace RemoteCommanderTray.Core;

/// <summary>
/// Safe, read-only classification of processes running outside this tray.
/// An unavailable inspection is not equivalent to an empty process list.
/// </summary>
public enum ExternalAgentPresence
{
    None,
    Conflict,
    Unknown,
}

/// <summary>
/// ProcessId is diagnostic only. The tray must never terminate an external process.
/// </summary>
public readonly record struct ExternalAgentCheck(ExternalAgentPresence Presence, int? ProcessId = null);

public interface IExternalAgentDetector
{
    ExternalAgentCheck Check();
}
