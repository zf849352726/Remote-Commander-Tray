using RemoteCommanderTray.Core;
using Xunit;

namespace RemoteCommanderTray.Core.Tests;

public sealed class LogRetentionTests : IDisposable
{
    private readonly string _folder = Path.Combine(Path.GetTempPath(), "rct-retention-" + Guid.NewGuid().ToString("N"));

    public LogRetentionTests() => Directory.CreateDirectory(_folder);

    private string Active => Path.Combine(_folder, "agent.log");

    [Fact]
    public void Defaults_use_independent_normal_and_verbose_limits()
    {
        var defaults = new TraySettings();
        Assert.Equal(1024L * 1024, defaults.LogMaxBytes);
        Assert.Equal(10, defaults.LogRetainedFiles);
        Assert.Equal(5L * 1024 * 1024, defaults.VerboseLogMaxBytes);
        Assert.Equal(4, defaults.VerboseLogRetainedFiles);
        Assert.False(defaults.VerboseAgentLog);

        var clamped = new TraySettings
        {
            VerboseLogMaxBytes = -1,
            VerboseLogRetainedFiles = -1,
        }.Normalized();
        Assert.Equal(64 * 1024, clamped.VerboseLogMaxBytes);
        Assert.Equal(0, clamped.VerboseLogRetainedFiles);
    }

    [Fact]
    public void Startup_removes_expired_rotations_but_not_other_files()
    {
        var recent = Active + ".1";
        var old = Active + ".2";
        var other = Active + ".tmp";
        var verbose = Path.Combine(_folder, "agent-verbose.log.1");
        foreach (var file in new[] { recent, old, other, verbose })
            File.WriteAllText(file, "test");

        var tenDaysAgo = DateTime.UtcNow.AddDays(-10);
        File.SetLastWriteTimeUtc(old, tenDaysAgo);
        File.SetCreationTimeUtc(old, tenDaysAgo);
        File.SetLastWriteTimeUtc(other, tenDaysAgo);
        File.SetCreationTimeUtc(other, tenDaysAgo);
        File.SetLastWriteTimeUtc(verbose, tenDaysAgo);
        File.SetCreationTimeUtc(verbose, tenDaysAgo);

        using var log = new RollingFileLog(Active, 64 * 1024, 10);

        Assert.True(File.Exists(recent));
        Assert.False(File.Exists(old));
        Assert.True(File.Exists(other));
        Assert.True(File.Exists(verbose));
    }

    [Fact]
    public void Expired_active_file_is_retired_before_next_append()
    {
        File.WriteAllText(Active, "obsolete prior-run content");
        var old = DateTime.UtcNow.AddDays(-9);
        File.SetLastWriteTimeUtc(Active, old);
        File.SetCreationTimeUtc(Active, old);

        using var log = new RollingFileLog(Active, 64 * 1024, 2);
        log.Write(LogSource.Tray, "fresh content");

        Assert.True(File.Exists(Active));
        Assert.Contains("fresh content", File.ReadAllText(Active));
        Assert.DoesNotContain("obsolete prior-run content", File.ReadAllText(Active));
        Assert.False(File.Exists(Active + ".1"));
    }

    [Fact]
    public void Retained_count_applies_to_extra_legacy_rotations()
    {
        File.WriteAllText(Active + ".11", "legacy");
        File.WriteAllText(Active + ".1", "keep");
        using var log = new RollingFileLog(Active, 64 * 1024, 10);

        Assert.False(File.Exists(Active + ".11"));
        Assert.True(File.Exists(Active + ".1"));
    }

    [Fact]
    public void Maintenance_removes_expired_archive_without_deleting_active_file()
    {
        using var log = new RollingFileLog(Active, 64 * 1024, 3);
        log.Write(LogSource.Tray, "active");
        File.WriteAllText(Active + ".1", "obsolete");
        File.SetLastWriteTimeUtc(Active + ".1", DateTime.UtcNow.AddDays(-9));

        log.Maintain();

        Assert.True(File.Exists(Active));
        Assert.Contains("active", File.ReadAllText(Active));
        Assert.False(File.Exists(Active + ".1"),
            $"Archived file was not pruned; lastWrite={File.GetLastWriteTimeUtc(Active + ".1"):O} now={DateTime.UtcNow:O}");
    }

    [Fact]
    public async Task Concurrent_writes_and_maintenance_keep_a_valid_active_log()
    {
        using var log = new RollingFileLog(Active, 16 * 1024, 2);
        var writers = Enumerable.Range(0, 5).Select(n => Task.Run(() =>
        {
            for (var i = 0; i < 75; i++)
                log.Write(LogSource.Tray, $"writer {n} line {i}");
        }));
        var cleanup = Task.Run(() =>
        {
            for (var i = 0; i < 75; i++) log.Maintain();
        });

        await Task.WhenAll(writers.Append(cleanup));

        Assert.True(File.Exists(Active));
        Assert.True(new FileInfo(Active).Length <= 16 * 1024);
        Assert.True(File.Exists(Active + ".1"));
        Assert.False(File.Exists(Active + ".3"));
        Assert.All(log.Tail(5), line => Assert.Contains("[tray]", line));
    }

    [Fact]
    public void Separate_verbose_rolling_does_not_change_standard_log()
    {
        var verbosePath = Path.Combine(_folder, "agent-verbose.log");
        using var normal = new RollingFileLog(Active, 16 * 1024, 10);
        using var verbose = new RollingFileLog(verbosePath, 16 * 1024, 4);

        normal.Write(LogSource.Tray, "safe ordinary message");
        for (var i = 0; i < 30; i++) verbose.Write(LogSource.Agent, new string('v', 1024));

        Assert.Contains("safe ordinary message", File.ReadAllText(Active));
        Assert.True(File.Exists(verbosePath + ".1"));
        Assert.False(File.Exists(Active + ".1"));
    }

    [Fact]
    public void Newlines_cannot_forge_second_log_row_and_secrets_are_redacted()
    {
        using var log = new RollingFileLog(Active, 64 * 1024, 2);
        log.Write(LogSource.Agent, "access_token=abcdef0123456789\n[tray] fabricated entry");

        var lines = File.ReadAllLines(Active);
        Assert.Single(lines);
        Assert.DoesNotContain("abcdef0123456789", lines[0]);
        Assert.Contains("\\n[tray] fabricated entry", lines[0]);
    }

    [Fact]
    public void Diagnostics_never_include_verbose_tail_or_credentials()
    {
        var confidential = "credit_card_or_sensitive_payload_abcdef";
        var ctx = new DiagnosticsContext("1.0", "Windows", "X64", confidential, confidential, StartupState.Enabled);
        var report = DiagnosticsReport.Build(AgentSnapshot.Initial, ctx, [confidential]);
        Assert.DoesNotContain(confidential, report);
        Assert.Contains("not included", report);
    }

    [Fact]
    public void Multibyte_input_is_truncated_without_exceeding_the_byte_limit()
    {
        using var log = new RollingFileLog(Active, 16 * 1024, 2);
        log.Write(LogSource.Agent, new string('中', 10_000));

        Assert.True(new FileInfo(Active).Length <= 16 * 1024);
        Assert.Contains("<event truncated>", File.ReadAllText(Active));
    }

    [Fact]
    public void A_locked_expired_archive_does_not_block_pruning_other_archives()
    {
        using var log = new RollingFileLog(Active, 64 * 1024, 3);
        log.Write(LogSource.Tray, "still active");
        File.WriteAllText(Active + ".1", "locked");
        File.WriteAllText(Active + ".2", "obsolete");
        var old = DateTime.UtcNow.AddDays(-9);
        File.SetLastWriteTimeUtc(Active + ".1", old);
        File.SetLastWriteTimeUtc(Active + ".2", old);

        using (var held = new FileStream(Active + ".1", FileMode.Open, FileAccess.Read, FileShare.None))
        {
            log.Maintain();
            Assert.True(File.Exists(Active));
            Assert.True(File.Exists(Active + ".1"));
            Assert.False(File.Exists(Active + ".2"));
        }

        log.Maintain();
        Assert.False(File.Exists(Active + ".1"));
    }

    public void Dispose()
    {
        try { Directory.Delete(_folder, true); } catch (IOException) { }
    }
}
