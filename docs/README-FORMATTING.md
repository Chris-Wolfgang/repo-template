# Code Formatting

This repository uses `dotnet format` to enforce consistent C# code style.

## Prerequisites

The `dotnet format` command is **built into the .NET SDK** starting with .NET 6 — no separate tool installation is needed. In practice `dotnet format` still has to load and evaluate the project, so you need an SDK new enough to handle this repo's target frameworks: use the SDK version(s) installed by `.github/workflows/pr.yaml` (and `global.json` if present). The latest stable .NET SDK is generally a safe choice.

> **Note:** The standalone `dotnet-format` global tool was deprecated when `dotnet format` was integrated into the .NET 6 SDK in August 2021.

## For Developers

### Before Committing

Run the formatting script with PowerShell Core (`pwsh`) on any supported platform:

```powershell
.\scripts\format.ps1
```

Or check without making changes:

```powershell
.\scripts\format.ps1 -Check
```

### Manual Formatting

```bash
dotnet format
```

### Verify Without Modifying Files

```bash
dotnet format --verify-no-changes
```

This is useful as a pre-commit guard or in a CI step if the repo opts in to enforcing formatting at PR time. By default, the standard PR workflow does **not** run `dotnet format --verify-no-changes`; formatting is treated as a developer-side hygiene step driven by `.editorconfig` and IDE-on-save behavior.

## Configuration

Code style rules are defined in `.editorconfig` at the repository root. `.editorconfig` is the source of truth — anything in this document that conflicts with `.editorconfig` should be considered out of date.

## Local Enforcement

Code formatting is enforced locally via `.editorconfig` and `dotnet format`. Run the formatting script before submitting a PR. If the repo has opted into a CI formatting check, the PR workflow will fail on unformatted code; resolve by running `.\scripts\format.ps1` locally and pushing the resulting changes.

## IDE Integration

Most IDEs automatically read `.editorconfig`:

- **Visual Studio**: Built-in support, formats on save (Tools → Options → Text Editor → C# → Code Style)
- **VS Code**: Install "EditorConfig for VS Code" extension
- **JetBrains Rider**: Built-in support

## Formatting Rules

Authoritative rules live in `.editorconfig` (and `.gitattributes` for line endings, which enforces LF across all text file types in this repo — including `*.ps1`, which historically used CRLF but is now LF for cross-platform shebang compatibility). The list below is a quick orientation; check those files for the binding values:

- **Indentation**: 4 spaces for C#, 2 for XML/JSON (per `.editorconfig`)
- **Braces**: Opening brace on its own line
- **Line endings**: LF for all text files (per `.gitattributes`), including PowerShell scripts
- **Trailing whitespace**: Removed
- **Using directives**: System namespaces first, sorted alphabetically
