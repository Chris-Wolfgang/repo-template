type: fix

`stryker.yaml`: the detect job no longer fails with exit 123 on a solution without .NET Framework projects, and a full `dotnet restore` precedes the Stryker run so per-TFM analysis works on a cold runner.
