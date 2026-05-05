# Code Formatting

This repository uses `dotnet format` to enforce consistent C# code style.

## Prerequisites

The `dotnet format` command is **built into the .NET SDK** starting with .NET 6 and later. Since this project requires .NET 8.0 SDK or later, you already have `dotnet format` available — no separate tool installation is needed.

> **Note:** The standalone `dotnet-format` global tool was deprecated when `dotnet format` was integrated into the .NET 6 SDK in August 2021.

## For Developers

### Before Committing

Run the formatting script with PowerShell Core (`pwsh`) on any supported platform:

```powershell
.\format.ps1
```

Or check without making changes:

```powershell
.\format.ps1 -Check
```

### Manual Formatting

```bash
dotnet format
```

### Check Formatting (like CI does)

```bash
dotnet format --verify-no-changes
```

## Configuration

Code style rules are defined in `.editorconfig` at the repository root.

## CI/CD

All pull requests are automatically checked for proper formatting. PRs with formatting issues will fail the build.

### If CI Fails

1. Run `.\format.ps1` locally
2. Review the changes
3. Commit and push the formatted code

## IDE Integration

Most IDEs automatically read `.editorconfig`:

- **Visual Studio**: Built-in support, formats on save (Tools → Options → Text Editor → C# → Code Style)
- **VS Code**: Install "EditorConfig for VS Code" extension
- **JetBrains Rider**: Built-in support

## Formatting Rules

Key style rules:
- **Indentation**: 4 spaces for C# (with `switch` case contents not additionally indented when inside a block, per `.editorconfig`), 2 for XML/JSON
- **Braces**: Opening brace on new line
- **Line endings**: LF (Unix style)
- **Trailing whitespace**: Removed
- **Using directives**: System namespaces first, sorted alphabetically
