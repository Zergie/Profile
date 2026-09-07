---
name: azure-devops
description: Operate Azure DevOps Services through Azure CLI. Use when the user wants to inspect or change Azure Boards work items, Repos or pull requests, Pipelines or builds, Artifacts, projects or teams, service connections, policies, permissions, or another Azure DevOps resource.
compatibility: Requires Azure CLI with the azure-devops extension and access to Azure DevOps Services. The extension does not support Azure DevOps Server.
---

# Azure DevOps

Use the `az` CLI as the control plane for Azure DevOps. Work **target-first**: resolve the organization, project, and resource identity before issuing an operation.

## Process

### 1. Resolve the target

Extract the organization, project, repository, pipeline, work item, or other identifiers from the request and current context.

When context is missing, inspect it without changing configuration:

```powershell
git remote -v
az devops configure --list
```

Use this precedence:

1. Values stated by the user.
2. Explicit command arguments already established in the conversation.
3. Organization and project detected from the current Git checkout.
4. Existing Azure DevOps CLI defaults.

Pass `--organization` and `--project` explicitly when practical. Change persistent defaults with `az devops configure --defaults ...` only when the user asks to configure them. If multiple targets remain equally plausible, ask which one to use.

Completion criterion: every scope required by the intended command is known, and any human-readable resource name has been resolved to a unique resource.

### 2. Establish capability and access

Check the local tools before relying on them:

```powershell
az version
az extension show --name azure-devops
```

If the extension is absent, install it with `az extension add --name azure-devops` when setup is within the request; otherwise tell the user what is missing.

Use existing authentication first. Prefer Microsoft Entra authentication through `az login`. Use `az devops login` or `AZURE_DEVOPS_EXT_PAT` only when PAT authentication is required by the environment. Ask the user to enter credentials through the CLI or secret store; never request, print, persist, or embed a token in chat, source files, command arguments, or logs.

Probe access with the narrowest relevant read command. Distinguish authentication failure, authorization failure, target-not-found, and unsupported-command errors because each requires a different remedy.

Completion criterion: the Azure DevOps extension is available and a relevant read either succeeds or yields a specific access/capability error to report.

### 3. Choose the narrowest CLI operation

Prefer the first-party command groups:

- `az boards` for work items and Boards queries.
- `az repos` for repositories, pull requests, policies, and reviewer metadata.
- `az pipelines` for pipeline definitions, runs, variables, folders, and queues.
- `az artifacts` for Azure Artifacts and Universal Packages.
- `az devops` for projects, teams, service endpoints, extensions, security, and organization-level operations.

Use native `git` for local Git data-plane work such as diffing, committing, fetching, and pushing; use `az repos` for Azure DevOps repository and pull-request control-plane operations.

Consult only the relevant section of [references/command-map.md](references/command-map.md) when mapping a request to a command. When flags or behavior are uncertain, inspect `az <group> <command> --help` before execution rather than guessing.

Request JSON for machine reasoning and narrow it with `--query` when that reduces output. Use `--output table` only for a user-facing display. Avoid `--open` unless the user asks to open a browser.

Completion criterion: the selected command is the narrowest supported operation and its required arguments have been checked against local help.

### 4. Execute proportionately

For reads, run the command directly.

For creates and updates explicitly requested by the user, inspect the current state, execute once, then read the resource back. Prefer stable IDs over display names in mutations.

Before destructive, irreversible, permission-changing, secret-changing, or broad multi-resource operations, show the exact target and effect and obtain confirmation unless the user already authorized that exact operation. Use concurrency or revision fields when the API exposes them.

Keep secrets out of output. Do not enable `--debug` when credentials or secret-bearing payloads might appear. Put complex request bodies in a temporary JSON file instead of fighting shell quoting, and remove the file after the request when it contains sensitive material.

Completion criterion: the command has a single understood blast radius and its result is captured without exposing secrets.

### 5. Fall back through `az devops invoke`

When no dedicated Azure DevOps CLI command covers the operation, stay inside the Azure CLI and use `az devops invoke`. First discover the exact area/resource and consult the matching official Azure DevOps REST reference for its route and API version.

Use JSON output because the response shape of `az devops invoke` is not fixed. Prefer `--in-file` for request bodies. Do not invent route parameters, resource names, or API versions.

Use another client only when both the dedicated CLI and `az devops invoke` cannot perform the task, and explain why the fallback is necessary before using it.

Completion criterion: either the dedicated command succeeded, or the REST fallback is tied to a documented area, resource, route, and API version.

### 6. Verify and report

Read back every changed resource with a separate command. For asynchronous operations, report the operation or run ID and distinguish queued/in-progress state from completion.

Return a concise action report containing:

- organization and project;
- resource type, name, and stable ID;
- action taken or query answered;
- verified final state;
- URL when the CLI returns one;
- any remaining user action.

Completion criterion: every requested operation is accounted for and every mutation has a read-back or an explicit reason verification is pending.

## Sources

- [Get started with Azure DevOps CLI](https://learn.microsoft.com/en-us/azure/devops/cli/)
- [`az devops` command reference](https://learn.microsoft.com/en-us/cli/azure/devops)
- [Azure DevOps authentication guidance](https://learn.microsoft.com/en-us/azure/devops/integrate/get-started/authentication/authentication-guidance)
- [Azure DevOps REST API reference](https://learn.microsoft.com/en-us/rest/api/azure/devops/)
