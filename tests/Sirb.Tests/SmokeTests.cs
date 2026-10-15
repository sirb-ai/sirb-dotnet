using System.Reflection;
using System.Text.Json;

namespace Sirb.Tests;

/// <summary>
/// Smoke tests for the solution layout. They guard the "thin core" layering from CLAUDE.md:
/// Sirb.Runtime builds on Sirb.Core, and Sirb.Core never depends on the runtime, the UI kit
/// or the CLI. Replace with behavioural tests as conformance fixtures from sirb-spec land.
/// </summary>
/// <remarks>
/// Layering is read from the test host's deps.json (the resolved project/package graph) rather
/// than from assembly metadata, because the compiler drops references to assemblies whose types
/// are never used, which would make a metadata check pass or fail for the wrong reason.
/// </remarks>
public class SmokeTests
{
    [Fact]
    public void CoreAndRuntimeAssembliesLoadWithExpectedNames()
    {
        Assert.Equal("Sirb.Core", typeof(Sirb.Core.Class1).Assembly.GetName().Name);
        Assert.Equal("Sirb.Runtime", typeof(Sirb.Runtime.Class1).Assembly.GetName().Name);
    }

    [Fact]
    public void RuntimeDependsOnCore()
    {
        Assert.Contains("Sirb.Core", DependenciesOf("Sirb.Runtime"));
    }

    [Theory]
    [InlineData("Sirb.Runtime")]
    [InlineData("Sirb.Blazor")]
    [InlineData("Sirb.Cli")]
    public void CoreDoesNotDependOnOuterLayers(string outerProject)
    {
        Assert.DoesNotContain(outerProject, DependenciesOf("Sirb.Core"));
    }

    /// <summary>Direct dependency names of <paramref name="library"/> from the deps.json graph.</summary>
    private static IReadOnlyList<string> DependenciesOf(string library)
    {
        var testAssembly = Assembly.GetExecutingAssembly().GetName().Name;
        var depsPath = Path.Combine(AppContext.BaseDirectory, $"{testAssembly}.deps.json");
        using var deps = JsonDocument.Parse(File.ReadAllText(depsPath));

        var targetName = deps.RootElement.GetProperty("runtimeTarget").GetProperty("name").GetString()!;
        var target = deps.RootElement.GetProperty("targets").GetProperty(targetName);

        var entry = target.EnumerateObject().SingleOrDefault(p => p.Name.StartsWith($"{library}/", StringComparison.Ordinal));
        Assert.True(entry.Value.ValueKind == JsonValueKind.Object, $"{library} not found in {depsPath}");

        return entry.Value.TryGetProperty("dependencies", out var dependencies)
            ? dependencies.EnumerateObject().Select(d => d.Name).ToList()
            : [];
    }
}
