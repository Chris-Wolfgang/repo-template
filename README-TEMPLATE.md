# {{PROJECT_NAME}}

{{PROJECT_DESCRIPTION}}

[![NuGet](https://img.shields.io/nuget/v/{{PACKAGE_NAME}}.svg?logo=nuget&label=NuGet)](https://www.nuget.org/packages/{{PACKAGE_NAME}}/)
[![Downloads](https://img.shields.io/nuget/dt/{{PACKAGE_NAME}}.svg?logo=nuget&label=downloads)](https://www.nuget.org/packages/{{PACKAGE_NAME}}/)
[![PR build](https://img.shields.io/github/actions/workflow/status/{{GITHUB_OWNER}}/{{REPO_NAME}}/pr.yaml?event=pull_request_target&label=PR%20build&logo=github)]({{GITHUB_REPO_URL}}/actions/workflows/pr.yaml)
[![release](https://img.shields.io/github/actions/workflow/status/{{GITHUB_OWNER}}/{{REPO_NAME}}/release.yaml?event=release&label=release&logo=github)]({{GITHUB_REPO_URL}}/actions/workflows/release.yaml)
[![License: {{LICENSE_TYPE}}](https://img.shields.io/badge/License-{{LICENSE_TYPE}}-blue.svg)](LICENSE)
[![.NET](https://img.shields.io/badge/.NET-Multi--Targeted-purple.svg)](https://dotnet.microsoft.com/)
[![GitHub](https://img.shields.io/badge/GitHub-Repository-181717?logo=github)]({{GITHUB_REPO_URL}})

---

## 📦 Installation

```bash
dotnet add package {{PACKAGE_NAME}}
```

**NuGet Package:** {{NUGET_STATUS}}

---

## 📄 License

This project is licensed under the **{{LICENSE_TYPE}} License**. See the [LICENSE](LICENSE) file for details.

---

## 📚 Documentation

- **GitHub Repository:** [{{GITHUB_REPO_URL}}]({{GITHUB_REPO_URL}})
- **API Documentation:** {{DOCS_URL}}
- **Formatting Guide:** [README-FORMATTING.md](README-FORMATTING.md)
- **Contributing Guide:** [CONTRIBUTING.md](CONTRIBUTING.md)

---

## 🚀 Quick Start

{{QUICK_START_EXAMPLE}}

---

## ✨ Features

{{FEATURES_TABLE}}

**Examples:**
{{FEATURE_EXAMPLES}}

---

## 🎯 Supported Frameworks

{{TARGET_FRAMEWORKS}}

See the [NuGet package page](https://www.nuget.org/packages/{{PACKAGE_NAME}}/) for the authoritative per-TFM compatibility matrix.

---

## 🔍 Code Quality & Static Analysis

This project enforces **strict code quality standards** through **7 specialized analyzers** and custom async-first rules:

### Analyzers in Use

1. **Microsoft.CodeAnalysis.NetAnalyzers** - Built-in .NET analyzers for correctness and performance
2. **Roslynator.Analyzers** - Advanced refactoring and code quality rules
3. **AsyncFixer** - Async/await best practices and anti-pattern detection
4. **Microsoft.VisualStudio.Threading.Analyzers** - Thread safety and async patterns
5. **Microsoft.CodeAnalysis.BannedApiAnalyzers** - Prevents usage of banned synchronous APIs
6. **Meziantou.Analyzer** - Comprehensive code quality rules
7. **SonarAnalyzer.CSharp** - Industry-standard code analysis

### Async-First Enforcement

This library uses **`BannedSymbols.txt`** to prohibit synchronous APIs and enforce async-first patterns:

**Blocked APIs Include:**
- ❌ `Task.Wait()`, `Task.Result` - Use `await` instead
- ❌ `Thread.Sleep()` - Use `await Task.Delay()` instead
- ❌ Synchronous file I/O (`File.ReadAllText`) - Use async versions
- ❌ Synchronous stream operations - Use `ReadAsync()`, `WriteAsync()`
- ❌ `Parallel.For/ForEach` - Use `Task.WhenAll()` or `Parallel.ForEachAsync()`
- ❌ Obsolete APIs (`WebClient`, `BinaryFormatter`)

**Why?** To ensure all code is **truly async** and **non-blocking** for optimal performance in async contexts.

---

## 🛠️ Building from Source

### Prerequisites
- [.NET 8.0 SDK](https://dotnet.microsoft.com/download) or later
- Optional: [PowerShell Core](https://github.com/PowerShell/PowerShell) for formatting scripts

### Build Steps

```bash
# Clone the repository
git clone {{GITHUB_REPO_URL}}.git
cd {{REPO_NAME}}

# Restore dependencies
dotnet restore

# Build the solution
dotnet build --configuration Release

# Run tests
dotnet test --configuration Release

# Run code formatting (PowerShell Core)
pwsh ./format.ps1
```

### Code Formatting

This project uses `.editorconfig` and `dotnet format`:

```bash
# Format code
dotnet format

# Verify formatting (as CI does)
dotnet format --verify-no-changes
```

See [README-FORMATTING.md](README-FORMATTING.md) for detailed formatting guidelines.

### Building Documentation

This project uses [DocFX](https://dotnet.github.io/docfx/) to generate API documentation:

```bash
# Install DocFX (one-time setup)
dotnet tool install -g docfx

# Generate API metadata and build documentation
cd docfx_project
docfx metadata  # Extract API metadata from source code
docfx build     # Build HTML documentation

# Documentation is generated in the docs/ folder at the repository root
```

The documentation is automatically built and deployed to GitHub Pages when changes are pushed to the `main` branch.

**Local Preview:**
```bash
# Serve documentation locally (with live reload)
cd docfx_project
docfx build --serve

# Open http://localhost:8080 in your browser
```

**Documentation Structure:**
- `docfx_project/` - DocFX configuration and source files
- `docs/` - Generated HTML documentation (published to GitHub Pages)
- `docfx_project/index.md` - Main landing page content
- `docfx_project/docs/` - Additional documentation articles
- `docfx_project/api/` - Auto-generated API reference YAML files

---

## 🤝 Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for:
- Code quality standards
- Build and test instructions
- Pull request guidelines
- Analyzer configuration details

---


## 🙏 Acknowledgments

{{ACKNOWLEDGMENTS}}
