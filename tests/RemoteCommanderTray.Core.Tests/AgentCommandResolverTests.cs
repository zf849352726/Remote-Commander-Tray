using RemoteCommanderTray.Core;
using Xunit;

namespace RemoteCommanderTray.Core.Tests;

public sealed class AgentCommandResolverTests
{
    private const string NodeExe = @"C:\Program Files\nodejs\node.exe";
    private const string PackageEntry =
        @"C:\Users\peter\AppData\Roaming\npm\node_modules\@wonderwhy-er\desktop-commander\dist\index.js";
    private const string PackageManifest =
        @"C:\Users\peter\AppData\Roaming\npm\node_modules\@wonderwhy-er\desktop-commander\package.json";

    [Fact]
    public void Pinned_global_install_resolves_to_node_without_shell_or_network()
    {
        var env = Installed();
        var resolution = new AgentCommandResolver(env).Resolve(AgentCommand.Remote, new TraySettings());

        Assert.True(resolution.Found);
        Assert.Equal(NodeExe, resolution.Spec!.FileName);
        Assert.Equal($"\"{PackageEntry}\" remote", resolution.Spec.Arguments);
        Assert.DoesNotContain("npx", resolution.Spec.Arguments, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Finds_pinned_global_npm_install_next_to_nvm_node_on_D_drive()
    {
        const string node = @"D:\nvm4w\nodejs\node.exe";
        const string entry = @"D:\nvm4w\nodejs\node_modules\@wonderwhy-er\desktop-commander\dist\index.js";
        const string manifest = @"D:\nvm4w\nodejs\node_modules\@wonderwhy-er\desktop-commander\package.json";
        var env = new FakeEnvironment
        {
            ManifestJson = """{"name":"@wonderwhy-er/desktop-commander","version":"0.3.0"}""",
            ManifestPath = manifest,
        };
        env.Variables["PATH"] = @"D:\nvm4w\nodejs";
        env.Files.UnionWith([node, entry, manifest]);

        var resolution = new AgentCommandResolver(env).Resolve(AgentCommand.Remote, new TraySettings());

        Assert.True(resolution.Found);
        Assert.Equal(node, resolution.Spec!.FileName);
        Assert.Equal($"\"{entry}\" remote", resolution.Spec.Arguments);
    }

    [Fact]
    public void Logout_uses_only_the_pinned_official_package()
    {
        var resolution = new AgentCommandResolver(Installed()).Resolve(AgentCommand.Logout, new TraySettings());

        Assert.True(resolution.Found);
        Assert.EndsWith("remote --logout", resolution.Spec!.Arguments);
    }

    [Theory]
    [InlineData("0.2.51")]
    [InlineData("0.3.1-alpha.2")]
    [InlineData("100.0.0")]
    public void Unverified_global_version_is_rejected_without_fallback(string version)
    {
        var env = Installed(version);
        env.Files.Add(@"C:\Users\peter\AppData\Roaming\npm\desktop-commander.cmd");
        env.Files.Add(@"C:\Program Files\nodejs\npx.cmd");

        var resolution = new AgentCommandResolver(env).Resolve(AgentCommand.Remote, new TraySettings());

        Assert.False(resolution.Found);
        Assert.Null(resolution.Spec);
        Assert.Contains(AgentCommandResolver.PinnedVersion, resolution.Problem);
        Assert.DoesNotContain("@latest", resolution.Problem, StringComparison.OrdinalIgnoreCase);
    }

    [Fact]
    public void Package_with_wrong_name_or_missing_manifest_is_rejected()
    {
        var env = Installed();
        env.ManifestJson = """{"name":"@not-desktop-commander","version":"0.3.0"}""";
        Assert.False(new AgentCommandResolver(env).Resolve(AgentCommand.Remote, new TraySettings()).Found);
        env.ManifestJson = null;
        Assert.False(new AgentCommandResolver(env).Resolve(AgentCommand.Remote, new TraySettings()).Found);
    }

    [Fact]
    public void A_global_shim_alone_is_not_sufficient_to_claim_a_verified_install()
    {
        var env = new FakeEnvironment();
        env.Variables["PATH"] = @"C:\Program Files\nodejs;C:\Users\peter\AppData\Roaming\npm";
        env.Files.UnionWith([
            NodeExe, @"C:\Users\peter\AppData\Roaming\npm\desktop-commander.cmd",
            @"C:\Program Files\nodejs\npx.cmd"
        ]);
        var resolution = new AgentCommandResolver(env).Resolve(AgentCommand.Remote, new TraySettings());
        Assert.False(resolution.Found);
        Assert.Contains("npm install -g", resolution.Problem);
    }

    [Fact]
    public void An_explicit_override_is_respected_as_user_configuration()
    {
        var settings = new TraySettings
        {
            AgentExecutable = @"D:\tools\dc.exe",
            AgentArguments = "--verbose",
        };
        var resolution = new AgentCommandResolver(new FakeEnvironment())
            .Resolve(AgentCommand.Remote, settings);
        Assert.Equal(@"D:\tools\dc.exe", resolution.Spec!.FileName);
        Assert.Equal("--verbose remote", resolution.Spec.Arguments);
    }

    [Fact]
    public void Explains_itself_when_nothing_is_installed()
    {
        var resolution = new AgentCommandResolver(new FakeEnvironment())
            .Resolve(AgentCommand.Remote, new TraySettings());

        Assert.False(resolution.Found);
        Assert.Contains($"npm install -g {AgentCommandResolver.PackageName}@{AgentCommandResolver.PinnedVersion}", resolution.Problem);
    }

    private static FakeEnvironment Installed(string version = AgentCommandResolver.PinnedVersion)
    {
        var env = new FakeEnvironment { ManifestJson = $$"""{"name":"@wonderwhy-er/desktop-commander","version":"{{version}}"}""" };
        env.Variables["PATH"] = @"C:\Windows;C:\Program Files\nodejs";
        env.Variables["APPDATA"] = @"C:\Users\peter\AppData\Roaming";
        env.Variables["ProgramFiles"] = @"C:\Program Files";
        env.Files.UnionWith([NodeExe, PackageEntry, PackageManifest]);
        return env;
    }

    private sealed class FakeEnvironment : IAgentEnvironment
    {
        public Dictionary<string, string> Variables { get; } = new(StringComparer.OrdinalIgnoreCase);
        public HashSet<string> Files { get; } = new(StringComparer.OrdinalIgnoreCase);
        public string? ManifestJson { get; set; }
        public string ManifestPath { get; set; } = PackageManifest;

        public bool FileExists(string path) => Files.Contains(path);
        public string? GetVariable(string name) => Variables.GetValueOrDefault(name);
        public string? ReadAllText(string path) => path == ManifestPath ? ManifestJson : null;
    }
}
