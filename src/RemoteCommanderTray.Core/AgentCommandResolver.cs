using System.Text.Json;

namespace RemoteCommanderTray.Core;

/// <summary>Filesystem and environment lookups, abstracted so resolution can be unit-tested.</summary>
public interface IAgentEnvironment
{
    bool FileExists(string path);

    string? GetVariable(string name);

    string? ReadAllText(string path);
}

/// <summary>Real process environment.</summary>
public sealed class SystemAgentEnvironment : IAgentEnvironment
{
    public bool FileExists(string path) => File.Exists(path);

    public string? GetVariable(string name) => Environment.GetEnvironmentVariable(name);

    public string? ReadAllText(string path)
    {
        try { return File.Exists(path) ? File.ReadAllText(path) : null; }
        catch (Exception ex) when (ex is IOException or UnauthorizedAccessException) { return null; }
    }
}

/// <summary>Outcome of looking for the official CLI.</summary>
/// <param name="Spec">How to launch it, or null when it was not found.</param>
/// <param name="Problem">Why it was not found, when <paramref name="Spec"/> is null.</param>
public readonly record struct AgentResolution(AgentLaunchSpec? Spec, string? Problem)
{
    public bool Found => Spec is not null;
}

/// <summary>
/// Works out how to start <c>desktop-commander remote</c> on this machine.
/// </summary>
/// <remarks>
/// Preference order, best first:
/// <list type="number">
/// <item>an explicit override in <c>settings.json</c>;</item>
/// <item><c>node.exe</c> plus the globally installed package's <c>dist/index.js</c>
/// after verifying an exact pinned version in package.json.</item>
/// <item>No fallback to shim, npx, @latest or downloads on Windows login.</item>
/// </list>
/// </remarks>
public sealed class AgentCommandResolver
{
    public const string PackageName = "@wonderwhy-er/desktop-commander";
    // Verified release candidate for this application. Changes require an explicit
    // release update and a real MCP roundtrip validation.
    public const string PinnedVersion = "0.3.0";

    private static readonly string[] PackageRelativePath =
        ["node_modules", "@wonderwhy-er", "desktop-commander", "dist", "index.js"];

    // Windows path conventions are hard-coded rather than taken from Path.Combine and
    // Path.PathSeparator: the paths being resolved are always Windows paths, whatever
    // host the unit tests happen to run on.
    private const char DirectorySeparator = '\\';
    private const char PathListSeparator = ';';

    private readonly IAgentEnvironment _environment;

    public AgentCommandResolver(IAgentEnvironment? environment = null)
        => _environment = environment ?? new SystemAgentEnvironment();

    public AgentResolution Resolve(AgentCommand command, TraySettings settings)
    {
        var suffix = command == AgentCommand.Logout ? "remote --logout" : "remote";

        if (!string.IsNullOrWhiteSpace(settings.AgentExecutable))
        {
            var exe = settings.AgentExecutable.Trim();
            var prefix = string.IsNullOrWhiteSpace(settings.AgentArguments)
                ? string.Empty
                : settings.AgentArguments.Trim() + " ";
            var spec = exe.EndsWith(".cmd", StringComparison.OrdinalIgnoreCase) || exe.EndsWith(".bat", StringComparison.OrdinalIgnoreCase)
                ? WrapInCmd($"{Quote(exe)} {prefix}{suffix}")
                : new AgentLaunchSpec(exe, prefix + suffix, $"{Quote(exe)} {prefix}{suffix}");
            return new AgentResolution(spec, null);
        }

        var node = FindNode();
        var entryPoint = FindVerifiedPackageEntryPoint(node);
        if (node is not null && entryPoint is not null)
        {
            var arguments = $"{Quote(entryPoint)} {suffix}";
            return new AgentResolution(
                new AgentLaunchSpec(node, arguments, $"{Quote(node)} {arguments}"),
                null);
        }

        return new AgentResolution(null,
            $"Desktop Commander Remote {PinnedVersion} is required as an exact global npm version. "
            + $"Run \"npm install -g {PackageName}@{PinnedVersion}\" yourself after checking existing "
            + "Remote instances. Startup will not download packages or use unverified npm shims.");
    }

    private AgentLaunchSpec WrapInCmd(string commandLine)
    {
        var comSpec = _environment.GetVariable("ComSpec");
        if (string.IsNullOrWhiteSpace(comSpec) || !_environment.FileExists(comSpec))
            comSpec = "cmd.exe";
        return new AgentLaunchSpec(comSpec, $"/d /s /c \"{commandLine}\"", commandLine);
    }
    private string? FindNode()
        => FindOnPath("node.exe")
           ?? FirstExisting(
               Combine(_environment.GetVariable("ProgramFiles"), "nodejs", "node.exe"),
               Combine(_environment.GetVariable("ProgramFiles(x86)"), "nodejs", "node.exe"),
               Combine(_environment.GetVariable("LOCALAPPDATA"), "Programs", "nodejs", "node.exe"));

    private string? FindVerifiedPackageEntryPoint(string? nodePath)
    {
        // nvm-windows commonly keeps the global npm modules beside node.exe on D:.
        // Looking beside the selected Node installation avoids any global npm
        // environment changes or implicit downloads.
        var roots = new List<string?>
        {
            string.IsNullOrWhiteSpace(nodePath) ? null : Path.GetDirectoryName(nodePath),
            _environment.GetVariable("NPM_CONFIG_PREFIX"),
            Combine(_environment.GetVariable("APPDATA"), "npm"),
            Combine(_environment.GetVariable("ProgramFiles"), "nodejs"),
            Combine(_environment.GetVariable("LOCALAPPDATA"), "Programs", "nodejs"),
            Combine(_environment.GetVariable("ProgramData"), "npm"),
        };

        foreach (var root in roots)
        {
            if (string.IsNullOrWhiteSpace(root))
            {
                continue;
            }

            var candidate = Combine(root, PackageRelativePath);
            var manifest = Combine(root, "node_modules", "@wonderwhy-er", "desktop-commander", "package.json");
            if (candidate is not null && manifest is not null && _environment.FileExists(candidate)
                && IsPinnedManifest(_environment.ReadAllText(manifest)))
            {
                return candidate;
            }
        }

        return null;
    }

    private static bool IsPinnedManifest(string? json)
    {
        if (string.IsNullOrWhiteSpace(json)) return false;
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            return root.TryGetProperty("name", out var name)
                && root.TryGetProperty("version", out var version)
                && string.Equals(name.GetString(), PackageName, StringComparison.Ordinal)
                && string.Equals(version.GetString(), PinnedVersion, StringComparison.Ordinal);
        }
        catch (JsonException) { return false; }
        catch (InvalidOperationException) { return false; }
    }

    private string? FindOnPath(string fileName)
    {
        var path = _environment.GetVariable("PATH");
        if (string.IsNullOrWhiteSpace(path))
        {
            return null;
        }

        foreach (var directory in path.Split(PathListSeparator, StringSplitOptions.RemoveEmptyEntries))
        {
            var trimmed = directory.Trim().Trim('"');
            if (trimmed.Length == 0)
            {
                continue;
            }

            var candidate = Combine(trimmed, fileName);
            if (candidate is not null && _environment.FileExists(candidate))
            {
                return candidate;
            }
        }

        return null;
    }

    private string? FirstExisting(params string?[] candidates)
        => candidates.FirstOrDefault(c => c is not null && _environment.FileExists(c));

    private static string? Combine(string? root, params string[] parts)
    {
        if (string.IsNullOrWhiteSpace(root))
        {
            return null;
        }

        var combined = root.TrimEnd(DirectorySeparator, '/');
        foreach (var part in parts)
        {
            combined += DirectorySeparator + part;
        }

        return combined;
    }

    /// <summary>
    /// Always quotes, rather than only when the path contains a space: "C:\Program
    /// Files" is the obvious case, but an unquoted path also lets cmd.exe interpret
    /// characters like &amp; and ^ that are legal in a Windows folder name.
    /// </summary>
    internal static string Quote(string value) => $"\"{value}\"";
}
