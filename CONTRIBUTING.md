# Contributing to {{PROJECT_NAME}}

Thank you for your interest in contributing to **{{PROJECT_NAME}}**! We welcome contributions to help improve this project.

## How Can You Contribute?

You can contribute in several ways:
- Reporting bugs
- Suggesting enhancements
- Submitting pull requests for new features or bug fixes
- Improving documentation
- Writing or improving tests

**Please note:** Before coding anything please check with me first by entering an issue and getting approval for it. PRs are more likely to get merged if I have agreed to the changes.

---

## Getting Started

1. **Fork the repository** and clone it locally.
2. **Enable the pre-commit secret scan** (once per clone). The repository ships a
   [gitleaks](https://github.com/gitleaks/gitleaks) hook in `.githooks/pre-commit` that blocks
   commits containing secrets (credentials, tokens, private keys); CI runs the same scan, so
   enabling it locally only saves you a failed PR check:
   ```sh
   git config core.hooksPath .githooks
   ```
   Install the `gitleaks` CLI: `winget install gitleaks` (Windows), `brew install gitleaks` (macOS), or a
   binary from the [releases page](https://github.com/gitleaks/gitleaks/releases) (Linux). Without it, the
   hook prints a warning and lets the commit through. `git commit --no-verify` skips it for one commit.
3. **Create a new branch** for your feature or bug fix:
   ```sh
   git checkout -b your-feature-name
   ```
4. **Make your changes** and commit them with clear messages:
   ```sh
   git commit -m "Describe your changes"
   ```
5. **Push your branch** to your fork:
   ```sh
   git push origin your-feature-name
   ```
6. **Open a pull request** describing your changes.

7. **PR Checks:**
   Opening a pull request runs these checks (`.github/workflows/pr.yaml` unless noted):
   - **Secrets Scan (gitleaks)** — the same scan as the pre-commit hook.
   - **Detect .NET Projects** — also the *protected-file guard*: a PR that changes `.editorconfig`,
     `Directory.Build.props/.targets`, `BannedSymbols.txt`, `*.globalconfig`, `*.ruleset`, `*.DotSettings`
     or anything under `.github/workflows/` fails here on purpose and is held for maintainer review
     (see [docs/WORKFLOW_SECURITY.md](docs/WORKFLOW_SECURITY.md)).
   - **Changelog Fragment Check** — a PR that touches `src/` must add a fragment (see below).
   - **ReSharper InspectCode** — error-severity findings fail; warnings go to the Security tab.
   - **Stage 1 (Linux), Stage 2 (Windows), Stage 3 (macOS)** — build and test every target framework
     of every test project, with coverage gates of **90 % line coverage for `src/`** and
     **100 % for `tests/`**. A framework on which zero tests ran fails the stage.
   - **Security Scan (DevSkim)** and **Security Scan (CodeQL)** (`codeql.yaml`).
   - **actionlint** and **zizmor** (`actions-audit.yaml`) on the workflow files themselves.
   - License audit and SBOM generation for the dependency closure (`license-audit.yaml`, `sbom.yaml`).

   The branch ruleset **requires** Detect .NET Projects, the three test stages, DevSkim, CodeQL,
   gitleaks and the Changelog Fragment Check to pass before merging. InspectCode, actionlint/zizmor,
   the license audit and the SBOM are advisory — they annotate the PR and the Security tab but do
   not block the merge on their own. If a check fails, read its log, fix, and push.
   `pwsh ./scripts/build-pr.ps1` reproduces the Windows stage locally (see *Build and Test* below).

8. **Add a changelog fragment** if the PR changes anything under `src/`:
   ```sh
   # changelog/unreleased/<short-change-name>.md
   type: fix

   One user-facing sentence describing what changed for the consumer.
   ```
   `type` is one of `breaking`, `feature`, `fix`, `docs`, `internal`. `CHANGELOG.md` is never edited by
   hand — the fragments are assembled into it at release time (`scripts/changelog.ps1 assemble`). A
   `src/` change with no user-visible effect can carry the `no-changelog` label instead. Details in
   [changelog/unreleased/README.md](changelog/unreleased/README.md).

---

## Code Quality Standards

This project maintains **extremely high code quality standards** through multiple layers of static analysis and automated enforcement.

### The Analyzers

Seven analyzers run on every build via `Directory.Build.props`; an eighth is opt-in per project:

1. **Microsoft.CodeAnalysis.NetAnalyzers** (Built-in .NET SDK)
   - Correctness, performance, and security rules
   - Latest analysis level enabled

2. **Roslynator.Analyzers**
   - 500+ refactoring and code quality rules
   - Advanced C# pattern detection

3. **AsyncFixer**
   - Detects common async/await anti-patterns (AsyncFixer01–05)
   - Flags missing or incorrect cancellation-token propagation
   - Prevents fire-and-forget async calls (`async void` outside event handlers)
   - NOTE: `ConfigureAwait(false)` enforcement is `CA2007` (a warning, so a
     Release error, in `src/`); Meziantou MA0004 and SonarAnalyzer S3216 report
     the same thing at suggestion level. AsyncFixer does not check it.

4. **Microsoft.VisualStudio.Threading.Analyzers**
   - Thread safety enforcement
   - Async method naming conventions
   - Deadlock prevention

5. **Microsoft.CodeAnalysis.BannedApiAnalyzers**
   - Blocks usage of APIs listed in `BannedSymbols.txt`
   - Enforces async-first patterns (see below)

6. **Meziantou.Analyzer**
   - Comprehensive code quality checks
   - Performance optimizations
   - Best practice enforcement

7. **SonarAnalyzer.CSharp**
   - Industry-standard code analysis
   - Security vulnerability detection
   - Code smell identification

8. **Microsoft.CodeAnalysis.PublicApiAnalyzers** (opt-in)
   - Tracks the public API surface in `PublicAPI.Shipped.txt` / `PublicAPI.Unshipped.txt`
   - Loaded only for a project that has either of those files next to its `.csproj` — add both to a
     library under `src/` to opt in. Don't put them in test, example or benchmark projects; the
     condition is per project, not per directory, so a stray baseline file opts that project in too
   - New or changed public members must be recorded in `PublicAPI.Unshipped.txt` or the build fails

### Async-First Enforcement

This library **prohibits synchronous blocking calls** via `BannedSymbols.txt`. The following APIs are **banned**:

#### ❌ Blocking Async Operations
```csharp
// Banned - blocks threads
task.Wait();
task.Result;
task.GetAwaiter().GetResult();
Task.WaitAll(tasks);
Parallel.ForEach(items, Work);

// Required - truly async
await task;
await Task.WhenAll(tasks);
await Task.WhenAll(items.Select(WorkAsync));      // every TFM
await Parallel.ForEachAsync(items, WorkAsync);    // .NET 6+ only
```

#### ❌ Synchronous I/O
```csharp
// Banned
File.ReadAllText(path);
stream.Read(buffer, 0, count);
source.CopyTo(destination);

// Required
await File.ReadAllTextAsync(path);
await stream.ReadAsync(buffer, 0, count);
await source.CopyToAsync(destination);
```

#### ❌ Thread Blocking
```csharp
// Banned
Thread.Sleep(1000);
Console.ReadLine();

// Required
await Task.Delay(1000);
// Avoid blocking console reads in async code
```

#### ❌ Obsolete/Insecure APIs
```csharp
// Banned
var client = new WebClient();
var formatter = new BinaryFormatter();
var now = DateTime.Now; // Use DateTimeOffset

// Required
var client = new HttpClient();
// Use System.Text.Json.JsonSerializer
var now = DateTimeOffset.UtcNow;
```

**Why?** This ensures all code is **truly asynchronous** and **non-blocking**, providing optimal performance in async contexts.

The complete list (65 symbols, each with the reason and the replacement) is [`BannedSymbols.txt`](BannedSymbols.txt).

---

## Build and Test Instructions

### Prerequisites
- Latest .NET SDK recommended (the CI matrix tests .NET Core 3.1, .NET 5.0-10.0 and .NET Framework 4.6.2-4.8.1; the SDK you actually need depends on your project's target frameworks. The template itself contains no csproj.)
- PowerShell 7 (`pwsh`) — every script under `scripts/` is PowerShell (`build-pr.ps1`, `changelog.ps1`, `format.ps1`, `setup.ps1`, ...)
- [gitleaks](https://github.com/gitleaks/gitleaks#installing) for the pre-commit hook (optional locally; CI runs it regardless)

### Build the Project

```bash
# Restore NuGet packages
dotnet restore

# Build in Release configuration (enforces all analyzers)
dotnet build --configuration Release
```

**Note:** Release builds treat all analyzer warnings as errors (`<TreatWarningsAsErrors>true</TreatWarningsAsErrors>`). Debug builds allow warnings to facilitate development.

### Run Tests

```bash
# Run all unit tests
dotnet test --configuration Release

# Run with coverage (if configured)
dotnet test --collect:"XPlat Code Coverage"
```

### Run the PR checks locally

```powershell
# Mirrors pr.yaml's Windows stage on this machine: build, every-TFM tests, coverage gates
# (90 % src / 100 % tests), DevSkim, gitleaks. The Linux and macOS stages only run in CI.
pwsh ./scripts/build-pr.ps1

# Skip the security scans or the coverage gate while iterating
pwsh ./scripts/build-pr.ps1 -SkipSecurity
pwsh ./scripts/build-pr.ps1 -SkipCoverage
```

### Code Formatting

This project uses `.editorconfig` for consistent code style:

```bash
# Format all code
dotnet format

# Check formatting without changes
dotnet format --verify-no-changes

# PowerShell formatting script
pwsh ./scripts/format.ps1
```

See [docs/README-FORMATTING.md](docs/README-FORMATTING.md) for detailed formatting rules.

---

## .editorconfig Rules

Key style rules:

- **Indentation:** 4 spaces (C#), 2 spaces (XML/JSON/YAML)
- **Line endings:** LF for every text file (`.gitattributes`), including `*.ps1`
- **Charset:** UTF-8
- **Trim trailing whitespace:** Yes
- **Final newline:** Yes
- **Braces:** Opening brace on its own line (Allman)
- **Using directives:** `System` namespaces first, then sorted
- **Naming:** PascalCase for types and non-field members, `I`-prefixed interfaces, camelCase for parameters/locals
- **File-scoped namespaces**, **`var`** where the type is apparent, **pattern-matching null checks**
  (`is null` / `is not null`): configured as suggestions, so the IDE nudges but the build does not fail on them

Analyzer severities (what *does* fail a Release build) are also set in `.editorconfig`, per directory:
`src/` is strictest, `tests/`, `benchmarks/` and `examples/` relax rules that only make sense for shipped code.

View the complete configuration in [.editorconfig](.editorconfig).

---

## Guidelines

- Follow the coding style used in the project.
- Write clear, concise commit messages.
- Add relevant tests for new features or bug fixes.
- Document any public APIs with XML documentation comments — `GenerateDocumentationFile` is on for every project under `src/`, so a missing comment (CS1591) fails the Release build.
- Ensure all analyzer warnings are addressed (they're treated as errors in Release builds).
- Use async/await patterns - no blocking calls allowed.
- Include `CancellationToken` parameters in async methods where appropriate.

---

## Pull Requests

If this repository requires linear history, stacked pull requests are restacked with `scripts/restack.ps1` after each merge — see [docs/STACKED-PRS.md](docs/STACKED-PRS.md).

Changes to protected configuration files (`.editorconfig`, `Directory.Build.props`, workflows, ...) are tested against the `main` versions, not yours, and the PR is held for maintainer review — keep them in their own PR, separate from code that depends on them. See [docs/WORKFLOW_SECURITY.md](docs/WORKFLOW_SECURITY.md#making-changes-to-protected-configuration-files).

- Ensure your pull request passes all tests and analyzer checks.
- Respond to review feedback in a timely manner.
- Reference related issues in your pull request description.
- Keep changes focused and atomic - one feature/fix per PR.
- Update documentation if you change public APIs.

---

## Code of Conduct

Please be respectful and considerate in all interactions. See [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for our community guidelines.

---

Thank you for contributing! 🎉
