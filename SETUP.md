# Setting Up Your Repository
After you create your repo from the template you will still need to configure some settings. 
Below is a list of what needs to be done. Once you have completed the checklist below you can delete this file

## Creating Your Repository

1. On the `Repositories` page click `New`
1. On the `Create a new repository` page enter
	1. `Repository name`
 	2. `Description`
  	3. Select `Public` or `Private`
1. `Start with a template` select `Chris-Wolfgang/repo-template`
1. `Include all branches` set `On` - this will include the `develop` branch. If you don't want the `develop` branch or if there are other branches you don't want you can leave this `off` and create the `develop` branch in your new repository


## Add Branch Protection Rules

1. Go to your repository’s Settings → Branches.
2. Under “Branch protection rules,” click `Add branch ruleset`
3. `Ruleset Name` enter `main`
4. `Target branches` click `Add target`
5. Select `Include by pattern`
6. `Branch naming pattern` enter `main`
7. Click `Add Inclusion pattern`


## Security Settings

Prevent Merging When Checks Fail
These settings require that all checks in the pr.yaml file succeed before you can merge a branch into main

1. Go to your repository’s Settings → Branches.
2. Under “Branch protection rules,” edit the rule for main.
3. Check “Require status checks to pass before merging.”
4. Select your PR workflow (it will be listed after it runs at least once).
5. Enable “Require branches to be up to date before merging.”
6. Check `Restrict deletions`
7. Check `Require a pull request before merging`
	1. Check `Dismiss stale pull request approvals when new commits are pushed`
 	2. Check `Require review from Code Owners`
	3. Check `Require pull request review from Copilot`
8. Check `Block force pushes`
9. Check `Require code scanning`


## Add Custom Labels

1. On the `Actions` tab select `Create Custom Labels`
2. Select `Run workflow`
3. Select `main` branch and click `Run`
You will need to create the following custom labels

If that doesn't work try the following

Go to `Issues` tab at the top of your repo and the select `Labels` and click `New label`

1. dependabot-dependencies
2. dependabot-security


## Creating the project

1. Create a blank solution and save it in the root folder
2. Add new projects to the solution. Each application project will be in its own folder in the /src folder
3. Add one or more test projects each in its own folder in the /tests folder
4. If the solution will have benchmark project add each project in its own folder under /benchmarks

```
root
├── MySolution.sln
├── src
│   ├── MyApp
│   │   └── MyApp.csproj
│   └── MyLib
│       └── MyLib.csproj
├── tests
│   ├── MyApp.Tests
│   │   └── MyApp.Tests.csproj
│   └── MyLib.Tests
│       └── MyLib.Tests.csproj
└── benchmarks
    └── MyApp.Benchmarks
        └── MyApp.Benchmarks.csproj
```
