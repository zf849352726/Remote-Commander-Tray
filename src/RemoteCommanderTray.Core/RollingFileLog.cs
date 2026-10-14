using System.Globalization;
using System.Text;

namespace RemoteCommanderTray.Core;

/// <summary>Where a log line came from.</summary>
public enum LogSource
{
    Tray,
    Agent,
    AgentError,
}

/// <summary>
/// Bounded append-only log: byte-size rotation, count cap and seven-day expiry.
/// Logging and maintenance share one lock so a live file is never pruned mid-write.
/// Raw opt-in logs remain sensitive; diagnostics never includes log content.
/// </summary>
public sealed class RollingFileLog : IDisposable
{
    private readonly string _path;
    private readonly long _maxBytes;
    private readonly int _retainedFiles;
    private readonly TimeSpan _maxAge;
    private readonly Func<DateTimeOffset> _clock;
    private readonly object _gate = new();
    private DateTimeOffset _nextMaintenanceUtc = DateTimeOffset.MinValue;
    private bool _disposed;

    public RollingFileLog(
        string path, long maxBytes, int retainedFiles,
        TimeSpan? maxAge = null, Func<DateTimeOffset>? clock = null)
    {
        _path = path;
        _maxBytes = Math.Max(16 * 1024, maxBytes);
        _retainedFiles = Math.Clamp(retainedFiles, 0, 100);
        _maxAge = maxAge ?? TimeSpan.FromDays(7);
        if (_maxAge <= TimeSpan.Zero)
            throw new ArgumentOutOfRangeException(nameof(maxAge), "Retention must be positive.");
        _clock = clock ?? (() => DateTimeOffset.UtcNow);
        Maintain(); // Handle previous-run files before the first write.
    }

    public string Path => _path;

    /// <summary>Writes one timestamped line. Failure never takes down the tray.</summary>
    public void Write(LogSource source, string message)
    {
        var tag = source switch
        {
            LogSource.Agent => "agent",
            LogSource.AgentError => "agent!",
            _ => "tray",
        };
        lock (_gate)
        {
            if (_disposed) return;
            try
            {
                EnsureDirectory();
                if (_clock() >= _nextMaintenanceUtc) PerformMaintenance();

                // Keep one physical record per event; do not permit forged log rows.
                var maxChars = (int)Math.Min(256 * 1024, _maxBytes / 2);
                if (message.Length > maxChars)
                    message = message[..maxChars] + " <event truncated>";
                message = SecretRedactor.Redact(message)
                    .Replace("\r", "\\r", StringComparison.Ordinal)
                    .Replace("\n", "\\n", StringComparison.Ordinal);
                var prefix = $"{_clock().ToLocalTime():yyyy-MM-dd HH:mm:ss.fff zzz} [{tag}] ";
                const string truncated = " <event truncated>";
                var reservedBytes = Encoding.UTF8.GetByteCount(prefix + Environment.NewLine + truncated);
                var allowedBytes = Math.Max(0, _maxBytes - reservedBytes);
                if (Encoding.UTF8.GetByteCount(message) > allowedBytes)
                {
                    // Trim by UTF-8 byte length, not characters. A CJK / emoji-heavy
                    // result must not bypass the file-size bound.
                    var low = 0;
                    var high = message.Length;
                    while (low < high)
                    {
                        var mid = low + (high - low + 1) / 2;
                        if (Encoding.UTF8.GetByteCount(message.AsSpan(0, mid)) <= allowedBytes)
                            low = mid;
                        else high = mid - 1;
                    }
                    message = message[..low] + truncated;
                }

                var line = prefix + message + Environment.NewLine;
                RotateIfNeeded(Encoding.UTF8.GetByteCount(line));
                File.AppendAllText(_path, line, new UTF8Encoding(false));
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException
                or NotSupportedException or ArgumentException or System.Security.SecurityException)
            {
                // Logging is best-effort, even when the disk is full or a file is locked.
            }
        }
    }

    /// <summary>
    /// Runs at startup, periodically, and before writes if the interval elapsed.
    /// Only manages the exact active basename and numeric rollover siblings.
    /// </summary>
    public void Maintain()
    {
        lock (_gate)
        {
            if (_disposed) return;
            try
            {
                EnsureDirectory();
                PerformMaintenance();
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException
                or NotSupportedException or ArgumentException or System.Security.SecurityException)
            {
                // A cleanup failure must never crash the agent or stop logging.
            }
        }
    }

    private void EnsureDirectory()
    {
        var directory = System.IO.Path.GetDirectoryName(_path);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
    }

    private void PerformMaintenance()
    {
        var now = _clock().UtcDateTime;
        var cutoff = now - _maxAge;
        try
        {
            // An active file can contain messages older than LastWriteTime. Its creation
            // time is a conservative upper bound for the oldest possible message.
            // Rotate before retirement so writers always append to a fresh active file.
            if (File.Exists(_path) && File.GetCreationTimeUtc(_path) < cutoff)
                RotateNow();

            // Known rotation indexes are checked directly: the cleanup must not
            // depend on filesystem wildcard matching or enumeration order.
            for (var i = 1; i <= _retainedFiles; i++)
            {
                var rotated = $"{_path}.{i}";
                try
                {
                    if (File.Exists(rotated) &&
                        (File.GetCreationTimeUtc(rotated) < cutoff ||
                         File.GetLastWriteTimeUtc(rotated) < cutoff))
                        File.Delete(rotated);
                }
                catch (Exception ex) when (ex is IOException or UnauthorizedAccessException
                    or System.Security.SecurityException)
                {
                    // One locked log must not block the cleanup of other files.
                }
            }

            // Drop any numeric archives beyond the current count (e.g. after changing
            // settings); never touch .tmp or verbose files with other basenames.
            var directory = System.IO.Path.GetDirectoryName(_path);
            if (directory is not null && Directory.Exists(directory))
            {
                var name = System.IO.Path.GetFileName(_path);
                foreach (var file in Directory.EnumerateFiles(directory, name + ".*"))
                {
                    var suffix = System.IO.Path.GetFileName(file)[(name.Length + 1)..];
                    if (!int.TryParse(suffix, NumberStyles.None, CultureInfo.InvariantCulture, out var number)
                        || number <= _retainedFiles) continue;
                    try { File.Delete(file); }
                    catch (Exception ex) when (ex is IOException or UnauthorizedAccessException
                        or System.Security.SecurityException) { }
                }
            }
        }
        finally
        {
            _nextMaintenanceUtc = _clock() + TimeSpan.FromMinutes(15);
        }
    }

    /// <summary>Returns the last count lines, newest last. Logs are never added to diagnostics.</summary>
    public IReadOnlyList<string> Tail(int count)
    {
        lock (_gate)
        {
            if (count <= 0 || _disposed) return [];
            try
            {
                if (!File.Exists(_path)) return [];
                var lines = File.ReadAllLines(_path);
                return lines.Length <= count ? lines : lines[^count..];
            }
            catch (Exception ex) when (ex is IOException or UnauthorizedAccessException)
            {
                return [];
            }
        }
    }

    private void RotateIfNeeded(int incomingBytes)
    {
        var info = new FileInfo(_path);
        if (info.Exists && info.Length + incomingBytes > _maxBytes)
            RotateNow();
    }

    private void RotateNow()
    {
        if (!File.Exists(_path)) return;
        if (_retainedFiles == 0)
        {
            File.Delete(_path);
            return;
        }
        var oldest = $"{_path}.{_retainedFiles}";
        if (File.Exists(oldest)) File.Delete(oldest);
        for (var i = _retainedFiles - 1; i >= 1; i--)
        {
            var from = $"{_path}.{i}";
            if (File.Exists(from)) File.Move(from, $"{_path}.{i + 1}", overwrite: true);
        }
        File.Move(_path, $"{_path}.1", overwrite: true);
    }

    public void Dispose()
    {
        lock (_gate) _disposed = true;
    }
}
