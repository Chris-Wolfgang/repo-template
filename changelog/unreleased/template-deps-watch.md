type: internal

A scheduled `Template Dependencies` workflow compares the `PackageReference` versions in `Directory.Build.props` against NuGet and keeps one tracking issue current. Dependabot cannot cover this file in the template: its NuGet updater needs a project file to anchor on and the template has none. The workflow skips itself in generated repositories, which have real projects and so are covered by Dependabot.
