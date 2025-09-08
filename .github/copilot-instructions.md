# Copilot Coding Agent Instructions

## Repository Summary

This is a **repository template** for creating new .NET repositories. It provides a standardized structure with comprehensive GitHub integration, CI/CD workflows, and development tooling. The template is designed for .NET 8.0 projects using C# and follows Microsoft's recommended project organization patterns.

**Repository Type**: Template (not a working project)  
**Target Platform**: .NET 8.0  
**Primary Language**: C#  
**Size**: Small template (~15 configuration files, empty project folders)  

## Build and Validation Instructions

### Prerequisites
- .NET 8.0.x SDK (always install if not present)
- ReportGenerator tool (installed via `dotnet tool install -g dotnet-reportgenerator-globaltool`)
- DevSkim CLI (installed via `dotnet tool install --global Microsoft.CST.DevSkim.CLI`)

### Build Process (For Repositories Created from This Template)
**IMPORTANT**: This template has no buildable projects. These commands apply to repositories created FROM this template.

1. **Restore Dependencies** (always run first):
   ```bash
   dotnet restore
   ```

2. **Build Solution**:
   ```bash
   dotnet build --no-restore --configuration Release
   ```

3. **Run Tests with Coverage**:
   ```bash
   # Find and test all test projects
   find ./tests -type f -name '*Test*.csproj' | while read proj; do
     dotnet test "$proj" --no-build --configuration Release --collect:"XPlat Code Coverage" --results-directory "./TestResults"
   done
   ```

4. **Generate Coverage Reports**:
   ```bash
   reportgenerator -reports:"TestResults/**/coverage.cobertura.xml" -targetdir:"CoverageReport" -reporttypes:"Html;TextSummary;MarkdownSummaryGithub;CsvSummary"
   ```

5. **Security Scanning**:
   ```bash
   devskim analyze --source-code . -f text --output-file devskim-results.txt -E
   ```

### Critical Build Requirements
- **Code Coverage**: Minimum 80% line coverage required for all projects
- **Security Scanning**: DevSkim must pass with no errors
- **Build Configuration**: Always use Release configuration for CI
- **Test Pattern**: Test projects must match `*Test*.csproj` pattern in `/tests` folder

### Common Issues and Workarounds
- **Timeout Issues**: Coverage and security scans can take 5-10 minutes for larger projects
- **Coverage Threshold Failures**: If below 80%, the build will fail - this is by design
- **Missing Test Projects**: The workflow expects at least one test project in `/tests` folder
- **DevSkim False Positives**: Review `devskim-results.txt` for any security findings

## Project Layout and Architecture

### Standard Directory Structure
```
root/
├── MySolution.sln              # Solution file (create in root)
├── src/                        # Application projects
│   ├── MyApp/
│   │   └── MyApp.csproj
│   └── MyLib/
│       └── MyLib.csproj
├── tests/                      # Test projects (required)
│   ├── MyApp.Tests/
│   │   └── MyApp.Tests.csproj
│   └── MyLib.Tests/
│       └── MyLib.Tests.csproj
├── benchmarks/                 # Performance benchmarks (optional)
│   └── MyApp.Benchmarks/
│       └── MyApp.Benchmarks.csproj
├── examples/                   # Example projects (optional)
├── docs/                       # Documentation
└── .github/                    # GitHub configuration
```

### Key Configuration Files
- **`.editorconfig`**: Code style rules (C# file-scoped namespaces, var preferences, analyzer severity)
- **`.gitignore`**: Comprehensive .NET gitignore (Visual Studio, build artifacts, packages)
- **`SETUP.md`**: Detailed repository setup instructions (delete after setup)
- **`CONTRIBUTING.md`**: Empty - populate with contribution guidelines
- **`CODE_OF_CONDUCT.md`**: Standard Contributor Covenant v2.0

### GitHub Integration
- **Workflows**: `.github/workflows/pr.yaml` - Comprehensive CI/CD pipeline
- **Issue Templates**: Bug reports (YAML) and feature requests (Markdown)
- **PR Template**: Structured pull request template with checklists
- **CODEOWNERS**: Default owner `@Chris-Wolfgang`, update usernames as needed
- **Dependabot**: Configured for NuGet packages in all project directories

### Continuous Integration Pipeline (`.github/workflows/pr.yaml`)
The workflow runs on pull requests to `main` branch and includes:

1. **Environment**: Ubuntu Latest with .NET 8.0.x
2. **Build Steps**: Checkout → Setup .NET → Restore → Build → Test → Coverage → Security
3. **Artifacts**: Coverage reports and DevSkim results uploaded
4. **Branch Protection**: Configured to require this workflow to pass before merging

**Security Note**: Workflow includes safeguard `if: github.repository != 'Chris-Wolfgang/repo-template'` to prevent running on the template itself.

### Branch Protection Configuration
When using this template, configure these settings in GitHub (detailed in `SETUP.md`):
- Require status checks to pass before merging
- Require branches to be up to date
- Require pull request reviews (including Copilot reviews)
- Restrict deletions and block force pushes
- Require code scanning

## Key Files and Locations

### Root Directory Files
- `README.md` - Basic template description (update for your project)
- `LICENSE` - Mozilla Public License 2.0
- `SETUP.md` - Template setup instructions (delete after setup)
- `.editorconfig` - Code style configuration
- `.gitignore` - .NET-specific gitignore

### GitHub Directory (`.github/`)
- `workflows/pr.yaml` - Main CI/CD pipeline
- `ISSUE_TEMPLATE/` - Bug report (YAML) and feature request templates
- `pull_request_template.md` - PR template with checklists
- `CODEOWNERS` - Code ownership rules
- `dependabot.yml` - Dependency update configuration

### Project Directories (Currently Empty in Template)
- `src/` - Application source code
- `tests/` - Unit and integration tests
- `benchmarks/` - Performance benchmarks
- `examples/` - Example usage projects
- `docs/` - Documentation (contains placeholder `index.html`)

## Agent Guidelines

### Trust These Instructions
This information has been validated against the template structure and GitHub workflows. **Only search for additional information if these instructions are incomplete or found to be incorrect.**

### When Working with This Template
1. **Creating New Projects**: Follow the structure outlined in `SETUP.md`
2. **Adding Dependencies**: Use `dotnet add package` commands
3. **Code Style**: Follow `.editorconfig` rules (file-scoped namespaces, explicit typing)
4. **Testing**: Ensure test projects follow `*Test*.csproj` naming convention
5. **Coverage**: Aim for >80% code coverage to pass CI
6. **Security**: Review DevSkim findings and address security concerns

### Validation Steps
Before submitting changes:
1. Run `dotnet restore && dotnet build --configuration Release`
2. Run tests with coverage collection
3. Verify coverage meets 80% threshold
4. Run DevSkim security scan
5. Ensure all GitHub Actions checks pass

This template provides a solid foundation for .NET projects with enterprise-grade CI/CD, security scanning, and development best practices built-in.