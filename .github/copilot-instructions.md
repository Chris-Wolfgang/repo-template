# Copilot Coding Agent Instructions

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Repository Summary

This is a **repository template** for creating new .NET repositories. It provides a standardized structure with comprehensive GitHub integration, CI/CD workflows, and development tooling. The template is designed for .NET 8.0 projects using C# and follows Microsoft's recommended project organization patterns.

**Repository Type**: Template (not a working project)  
**Target Platform**: .NET 8.0  
**Primary Language**: C#  
**Size**: Small template (~15 configuration files, empty project folders)  

## Working Effectively

### Prerequisites Installation
Install required tools with these exact commands:
```bash
# Install .NET 8.0 SDK if not present
# Download from: https://dotnet.microsoft.com/en-us/download/dotnet/8.0

# Install global tools (timing: ~30-60 seconds each)
dotnet tool install -g dotnet-reportgenerator-globaltool
dotnet tool install --global Microsoft.CST.DevSkim.CLI
```

### Build Process (For Repositories Created from This Template)
**CRITICAL**: This template has no buildable projects. These commands apply to repositories created FROM this template.

**NEVER CANCEL BUILDS OR TESTS** - Set timeouts of 300+ seconds for all commands.

1. **Restore Dependencies** (timing: 1-10 seconds, NEVER CANCEL):
   ```bash
   dotnet restore
   ```

2. **Build Solution** (timing: 1-30 seconds for small projects, NEVER CANCEL):
   ```bash
   dotnet build --no-restore --configuration Release
   ```

3. **Run Tests with Coverage** (timing: 2-15 seconds per test project, NEVER CANCEL):
   ```bash
   # Find and test all test projects
   find ./tests -type f -name '*Test*.csproj' | while read proj; do
     echo "Testing $proj"
     dotnet test "$proj" --no-build --configuration Release --collect:"XPlat Code Coverage" --results-directory "./TestResults"
   done
   ```

4. **Generate Coverage Reports** (timing: <1 second for small projects, up to 60 seconds for large ones, NEVER CANCEL):
   ```bash
   reportgenerator -reports:"TestResults/**/coverage.cobertura.xml" -targetdir:"CoverageReport" -reporttypes:"Html;TextSummary;MarkdownSummaryGithub;CsvSummary"
   ```

5. **Security Scanning** (timing: 1-10 seconds, NEVER CANCEL):
   ```bash
   devskim analyze --source-code . -f text --output-file devskim-results.txt -E
   ```

6. **Validate Coverage Thresholds** (timing: <1 second):
   ```bash
   # Check 80% coverage requirement
   failed_projects=""
   while read -r line; do
     module=$(echo "$line" | awk '{print $1}')
     percent=$(echo "$line" | awk '{print $NF}' | tr -d '%' | xargs)
     echo "Checking module: '$module', percent: '$percent'"
     if [[ "$percent" =~ ^[0-9]+$ ]]; then
       if [ "$percent" -lt 80 ]; then
         echo "FAIL: $module is below 80% ($percent%)"
         failed_projects="$failed_projects $module ($percent%)"
       else
         echo "PASS: $module meets coverage ($percent%)"
       fi
     fi
   done < <(grep -E '^[^ ].*[0-9]+%$' CoverageReport/Summary.txt | grep -v '^Summary')
   
   if [ -n "$failed_projects" ]; then
     echo "The following projects are below 80% line coverage:$failed_projects"
     exit 1
   fi
   ```

### Critical Build Requirements
- **Code Coverage**: Minimum 80% line coverage required for all projects
- **Security Scanning**: DevSkim must run without errors (exit code issues from generated files are normal)
- **Build Configuration**: Always use Release configuration for CI/CD
- **Test Pattern**: Test projects must match `*Test*.csproj` pattern in `/tests` folder

### Validation
Always manually validate changes after building:
1. **Build Validation**: Verify `dotnet build` succeeds with no warnings in Release mode
2. **Test Validation**: Confirm all tests pass and coverage reports generate
3. **Coverage Validation**: Check that `CoverageReport/Summary.txt` shows ≥80% for all modules
4. **Security Validation**: Review `devskim-results.txt` for actual security issues (ignore false positives from generated coverage files)
5. **CI Validation**: Ensure all GitHub Actions checks pass before merging

### Common Issues and Workarounds
- **Timeout Issues**: Use timeouts of 300+ seconds for all commands. Coverage and security scans can take several minutes for larger projects
- **Coverage Threshold Failures**: If below 80%, add more tests or mark uncoverable code with `[ExcludeFromCodeCoverage]`
- **Missing Test Projects**: The workflow expects at least one test project in `/tests` folder matching `*Test*.csproj`
- **DevSkim False Positives**: Coverage report JS files trigger security warnings - these are safe to ignore

## Common tasks
The following are outputs from frequently run commands. Reference them instead of viewing, searching, or running bash commands to save time.

### Repository Structure
```
/home/runner/work/repo-template/repo-template/
├── .editorconfig
├── .git/
├── .github/
│   ├── CODEOWNERS
│   ├── ISSUE_TEMPLATE/
│   │   ├── BUG_REPORT.yaml
│   │   └── feature_request.md
│   ├── copilot-instructions.md
│   ├── dependabot.yml
│   ├── pull_request_template.md
│   └── workflows/
│       └── pr.yaml
├── .gitignore
├── CODE_OF_CONDUCT.md
├── CONTRIBUTING.md (empty)
├── LICENSE (Mozilla Public License 2.0)
├── README.md
├── SETUP.md
├── benchmarks/
│   └── .placeholder
├── docs/
│   └── index.html
├── examples/
│   └── .placeholder.txt
├── src/
│   └── .placeholder
└── tests/
    └── .placeholder
```

### cat .editorconfig (Key Settings)
```ini
root = true

[*]
charset = utf-8
end_of_line = crlf
insert_final_newline = true
indent_style = tab
indent_size = 4

[*.cs]
# Use file-scoped namespaces
csharp_style_namespace_declarations = file_scoped:suggestion
# Prefer `var` when type is apparent
csharp_style_var_when_type_is_apparent = true:suggestion
# Treat warnings as errors for analyzers
dotnet_analyzer_diagnostic.severity = error
```

### GitHub Workflow Summary (.github/workflows/pr.yaml)
- **Trigger**: Pull requests to `main` branch
- **OS**: Ubuntu Latest
- **Runtime**: .NET 8.0.x
- **Safety Guard**: `if: github.repository != 'Chris-Wolfgang/repo-template'`
- **Steps**: Checkout → Setup .NET → Restore → Build → Test → Coverage → Security
- **Artifacts**: Coverage reports and DevSkim results uploaded
- **Required**: All steps must pass for PR to be mergeable

### Expected Project Structure (When Using Template)
```
MySolution.sln (root)
├── src/
│   ├── MyApp/
│   │   └── MyApp.csproj
│   └── MyLib/
│       └── MyLib.csproj
├── tests/ (REQUIRED)
│   ├── MyApp.Tests/
│   │   └── MyApp.Tests.csproj
│   └── MyLib.Tests/
│       └── MyLib.Tests.csproj
└── benchmarks/ (optional)
    └── MyApp.Benchmarks/
        └── MyApp.Benchmarks.csproj
```

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

### Validation Scenarios
After making changes, always test these specific scenarios:

1. **Create New Class Library** (timing: 3-5 seconds):
   ```bash
   cd src/MyProject && dotnet new classlib -n MyProject
   dotnet sln add src/MyProject/MyProject.csproj
   ```

2. **Create New Test Project** (timing: 10-15 seconds):
   ```bash
   cd tests && dotnet new xunit -n MyProject.Tests
   dotnet sln add tests/MyProject.Tests/MyProject.Tests.csproj
   cd MyProject.Tests && dotnet add reference ../../src/MyProject/MyProject.csproj
   ```

3. **Full Build and Test Cycle** (timing: 15-60 seconds total, NEVER CANCEL):
   ```bash
   dotnet restore
   dotnet build --no-restore --configuration Release
   find ./tests -type f -name '*Test*.csproj' | while read proj; do
     dotnet test "$proj" --no-build --configuration Release --collect:"XPlat Code Coverage" --results-directory "./TestResults"
   done
   reportgenerator -reports:"TestResults/**/coverage.cobertura.xml" -targetdir:"CoverageReport" -reporttypes:"Html;TextSummary;MarkdownSummaryGithub;CsvSummary"
   devskim analyze --source-code . -f text --output-file devskim-results.txt -E
   ```

4. **Coverage Validation Test**: Add a simple class and test to verify 80% threshold works:
   ```csharp
   // In src project
   public class Calculator 
   {
       public int Add(int a, int b) => a + b;
       public int Multiply(int a, int b) => a * b;  // Test both methods for 100% coverage
   }
   
   // In test project  
   [Fact] public void Add_ShouldWork() => Assert.Equal(5, new Calculator().Add(2, 3));
   [Fact] public void Multiply_ShouldWork() => Assert.Equal(20, new Calculator().Multiply(4, 5));
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