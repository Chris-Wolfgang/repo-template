# Setting Up Your Repo
After you create you repo from the template you will still need to configure some settings. 
Below is a list of what needs to be done. Once you have completed the checklist below you can delete this file


## Security Settings

Prevent Merging When Checks Fail
These settings require that all checks in the pr.yaml file succeed before you can merge a branch into main

1. Go to your repository’s Settings → Branches.
2. Under “Branch protection rules,” add or edit a rule for main.
3. Check “Require status checks to pass before merging.”
4. Select your PR workflow (it will be listed after it runs at least once).
5. Enable “Require branches to be up to date before merging.”
