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
2. **Create a new branch** for your feature or bug fix:
   ```sh
   git checkout -b your-feature-name
   ```
3. **Make your changes** and commit them with clear messages:
   ```sh
   git commit -m "Describe your changes"
   ```
4. **Push your branch** to your fork:
   ```sh
   git push origin your-feature-name
   ```
5. **Open a pull request** describing your changes.

6. **PR Checks:**  
   Once you create a pull request (PR), several Continuous Integration (CI) steps will run automatically. These may include:
   - Building the project
   - Running automated tests
   - Checking code style and linting
   - Running static analysis with multiple static analyzers (see list below)

   **It is important to make sure that all CI steps pass before your PR can be merged.**
   - If any CI step fails, please review the error messages and update your PR as needed.
   - Maintainers will review your PR once all checks have passed.

---

## Code Quality Standards

This project maintains **extremely high code quality standards** through multiple layers of static analysis and automated enforcement.

### The 7 Analyzers

All code is analyzed by these tools during build:

1. **Microsoft.CodeAnalysis.NetAnalyzers** (Built-in .NET SDK)
   - Correctness, performance, and security rules
   - Latest analysis level enabled

2. **Roslynator.Analyzers**
   - 500+ refactoring and code quality rules
   - Advanced C# pattern detection

3. **AsyncFixer**
   - Detects async/await anti-patterns
   - Ensures proper `ConfigureAwait()` usage
   - Prevents fire-and-forget async calls

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

### Async-First Enforcement

This library **prohibits synchronous blocking calls** via `BannedSymbols.txt`. The following APIs are **banned**:

#### ❌ Blocking Async Operations
```csharp
// Banned - blocks threads
task.Wait();
task.Result;
Task.WaitAll(tasks);

// Required - truly async
await task;
await Task.WhenAll(tasks);
```

#### ❌ Synchronous I/O
```csharp
// Banned
File.ReadAllText(path);
stream.Read(buffer, 0, count);
streamReader.ReadLine();

// Required
await File.ReadAllTextAsync(path);
await stream.ReadAsync(buffer, 0, count);
await streamReader.ReadLineAsync();
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

---

## Build and Test Instructions

### Prerequisites
- .NET 8.0 SDK or later
- PowerShell Core (optional, for formatting scripts)

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

### Code Formatting

This project uses `.editorconfig` for consistent code style:

```bash
# Format all code
dotnet format

# Check formatting without changes (CI mode)
dotnet format --verify-no-changes

# PowerShell formatting script
pwsh ./format.ps1
```

See [README-FORMATTING.md](README-FORMATTING.md) for detailed formatting rules.

---

## .editorconfig Rules

Key style rules enforced:

- **Indentation:** 4 spaces (C#), 2 spaces (XML/JSON)
- **Line endings:** LF (Unix-style)
- **Charset:** UTF-8
- **Trim trailing whitespace:** Yes
- **Final newline:** Yes
- **Braces:** New line style (Allman)
- **Naming:** PascalCase for public members, camelCase for parameters/locals
- **File-scoped namespaces:** Required in C# 10+
- **`var` preferences:** Use for built-in types and when type is obvious
- **Null checks:** Prefer pattern matching (`is null`, `is not null`)

View the complete configuration in [.editorconfig](.editorconfig).

---

## Guidelines

- Follow the coding style used in the project.
- Write clear, concise commit messages.
- Add relevant tests for new features or bug fixes.
- Document any public APIs with XML documentation comments.
- Ensure all analyzer warnings are addressed (they're treated as errors in Release builds).
- Use async/await patterns - no blocking calls allowed.
- Include `CancellationToken` parameters in async methods where appropriate.

---

## Pull Requests

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
