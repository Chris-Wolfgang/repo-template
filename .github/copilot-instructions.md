# Repository Template (.NET)
This repository is a template for creating .NET applications with comprehensive CI/CD pipelines, testing, and security scanning. It follows .NET project conventions with structured directories for source code, tests, benchmarks, and examples.

Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.

## Working Effectively

### Repository State
- This is a template repository - it contains placeholder directories but NO actual .NET projects by default
- The GitHub workflow (`.github/workflows/pr.yaml`) only runs when `github.repository != 'Chris-Wolfgang/repo-template'` to avoid failures in the template itself
- You MUST create actual .NET projects before build commands will work

### Setting Up Projects (Required Before Building)
Follow the structure described in `SETUP.md`:
- Create a solution file in root: `dotnet new sln -n YourSolution`
- Create application projects in `/src` folder: `dotnet new console -n YourApp -o src/YourApp`
- Create test projects in `/tests` folder: `dotnet new xunit -n YourApp.Tests -o tests/YourApp.Tests`
- Add projects to solution: `dotnet sln add src/YourApp/YourApp.csproj tests/YourApp.Tests/YourApp.Tests.csproj`
- Optional: Create benchmark projects in `/benchmarks` folder

### Build and Test Commands
Only run these commands AFTER creating actual .NET projects:

#### Prerequisites
- .NET 8.0.x SDK (confirmed working)
- `dotnet tool install -g dotnet-reportgenerator-globaltool` (takes ~2 seconds)
- `dotnet tool install --global Microsoft.CST.DevSkim.CLI` (takes ~2 seconds)

#### Core Build Process
- `dotnet restore` -- takes ~1-2 seconds with projects, FAILS without projects
- `dotnet build --no-restore --configuration Release` -- takes ~6 seconds. NEVER CANCEL. Set timeout to 10+ minutes.
- Test execution with coverage:
  ```bash
  find ./tests -type f -name '*Test*.csproj' | while read proj; do
    echo "Testing $proj"
    dotnet test "$proj" --no-build --configuration Release --collect:"XPlat Code Coverage" --results-directory "./TestResults"
  done
  ```
  -- takes ~4 seconds per test project. NEVER CANCEL. Set timeout to 15+ minutes.

#### Coverage Reporting
- `reportgenerator -reports:"TestResults/**/coverage.cobertura.xml" -targetdir:"CoverageReport" -reporttypes:"Html;TextSummary;MarkdownSummaryGithub;CsvSummary"` -- takes ~1 second
- Coverage threshold check is automated in the workflow and requires 80% line coverage

#### Security Scanning
- `devskim analyze --source-code . -f text --output-file devskim-results.txt -E` -- takes ~1 second. Exit code 28 indicates security issues found (this is normal).

### Running Applications
- Console applications: `dotnet run --project src/YourApp`
- Web applications: `dotnet run --project src/YourWebApp` (typically runs on localhost:5000 or localhost:5001)

## Validation
- ALWAYS create and test with actual .NET projects when making changes
- The template itself has NO buildable projects - commands will fail until projects are created
- ALWAYS run through at least one complete build → test → security scan cycle after making changes
- Run `dotnet --version` to confirm .NET 8.0.x is available
- ALWAYS run the full workflow commands to ensure CI compatibility

## Common Tasks

### Repository Structure
```
repo-template/
├── .github/
│   └── workflows/
│       └── pr.yaml          # Main CI/CD pipeline
├── src/                     # Application projects go here
├── tests/                   # Test projects go here  
├── benchmarks/              # Benchmark projects go here
├── examples/                # Example code goes here
├── docs/                    # Documentation
├── SETUP.md                 # Template setup instructions
├── README.md                # Project documentation
├── .editorconfig            # Code formatting rules
└── .gitignore               # .NET-specific ignore rules
```

### Key Files
- `.github/workflows/pr.yaml`: Defines CI/CD pipeline with build, test, coverage, and security scanning
- `SETUP.md`: Instructions for setting up a new repository from this template
- `.editorconfig`: Enforces C# coding standards and formatting rules
- `.gitignore`: Comprehensive .NET gitignore with Visual Studio and build artifact exclusions

### CI/CD Pipeline Details
The `pr.yaml` workflow includes:
1. .NET 8.0.x setup
2. Package restoration
3. Release build
4. Test execution with code coverage collection
5. Coverage report generation and 80% threshold enforcement
6. DevSkim security scanning
7. Artifact upload for coverage reports and security results

### Expected Command Failures in Template State
- `dotnet restore` -- FAILS with "MSB1003: Specify a project or solution file" (expected when no projects exist)
- `dotnet build` -- FAILS with same error (expected when no projects exist)  
- `dotnet test` -- FAILS with same error (expected when no projects exist)

### Working with the Template
1. NEVER try to build the template repository itself - it has no projects
2. ALWAYS create actual .NET projects first using the structure in `SETUP.md`
3. Use this template by clicking "Use this template" on GitHub, not by cloning directly
4. Delete `SETUP.md` after completing repository setup
5. The workflow automatically skips execution in the template repository itself