# Azure DevOps CLI command map

Read only the section matching the current task. Treat these as routing hints; confirm exact flags with local `--help` because extension versions differ.

## Organization, projects, and teams

```powershell
az devops project list
az devops project show --project <name-or-id>
az devops team list --project <name-or-id>
az devops team show --project <name-or-id> --team <name-or-id>
```

Use `az devops project create` or `delete` only for an explicit lifecycle request. Project deletion is destructive.

## Boards

```powershell
az boards work-item show --id <id> --expand all
az boards work-item create --type <type> --title <title>
az boards work-item update --id <id> --fields <field=value>
az boards query --wiql <query>
```

Read a work item before updating it. For relations, comments, or fields that are awkward in the dedicated command, inspect `az boards work-item relation` and local help before considering `az devops invoke`.

## Repositories and pull requests

```powershell
az repos list
az repos show --repository <name-or-id>
az repos pr list --repository <name-or-id>
az repos pr show --id <pull-request-id>
az repos pr create --repository <name-or-id> --source-branch <branch> --target-branch <branch> --title <title>
az repos pr update --id <pull-request-id>
```

Resolve branch names and inspect the pushed commits before creating a pull request. Use `git` for local repository operations and `az repos` for server-side repository, policy, and pull-request state.

## Pipelines and runs

```powershell
az pipelines list
az pipelines show --id <pipeline-id>
az pipelines run --id <pipeline-id>
az pipelines runs list --pipeline-ids <pipeline-id>
az pipelines runs show --id <run-id>
```

Treat queueing a run as asynchronous. Return the run ID and current state; wait or poll only when the user asked for completion.

Inspect the relevant subgroups for variables, variable groups, folders, build tags, releases, or agents. Secret variable values are write-only and must not appear in output.

## Artifacts

```powershell
az artifacts universal download --feed <feed> --name <package> --version <version> --path <path>
az artifacts universal publish --feed <feed> --name <package> --version <version> --path <path>
```

Confirm feed, package, version, and filesystem path before transferring data. Check dedicated `az artifacts` help first; use `az devops invoke` for feed-management operations not exposed by the installed extension.

## Service connections and administration

```powershell
az devops service-endpoint list --project <name-or-id>
az devops service-endpoint show --id <endpoint-id> --project <name-or-id>
az devops security group list
az devops security permission show --id <namespace-id>
```

Service connections and permissions can expose or change privileged access. Identify stable IDs, inspect the current state, redact authorization material, and apply the mutation guardrails from the main skill.

## REST fallback

Discover areas and resources before invoking one:

```powershell
az devops invoke --query "[?contains(area, 'Git')]"
az devops invoke --area <area> --resource <resource> --route-parameters <name=value> --query-parameters <name=value> --api-version <version> --http-method GET --output json
```

For writes, add `--in-file <payload.json>` and the documented HTTP method. Match the area, resource, route parameters, query parameters, and API version to the official REST operation; similar names across API areas are not interchangeable.
