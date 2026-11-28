type: internal

The analyzer package versions and the `codeql-action` pin now match what the fleet already runs: Roslynator 5.0.1, Microsoft.VisualStudio.Threading.Analyzers 18.12.1, BannedApiAnalyzers 5.6.0, Meziantou.Analyzer 3.0.342, SonarAnalyzer.CSharp 10.37.0.15768, codeql-action v4.38.3. The `Microsoft.SourceLink.GitHub` package reference is gone: the SDK's built-in SourceLink (8.0+) does the same job.
