# Cloud sandbox setup

For cloud SBX sandboxes of type `opencode`. Cloud runtime validation is pending.
Use a disposable sandbox first. Run host commands in **Windows PowerShell**
and deployment commands in **sandbox Bash**. Skip completed setup.

## Windows setup

Use Windows PowerShell 5.1 or PowerShell 7 in a terminal. Install the
[SBX CLI](https://docs.docker.com/ai/sandboxes/) first. Your Docker account
must have cloud access and permission to create billable sandboxes. Use a
disposable sandbox for the first test. This block has not passed a live test.
Cloud creation with static MCP is currently blocked in the reported v0.53.0
setup by a missing secret named `docker`. See the recovery section below.

Paste the **whole block** at once. It asks for the sandbox name first. It
checks cloud access, prepares credentials, adds initial network exceptions,
creates an `opencode` sandbox, and connects Context7. Then it opens sandbox
Bash for you to paste `sbx_local_opencode_deploy.sh`. It does not run the
installer. Creation uses 2 CPUs, 4 GiB, and a two-hour timeout with the stop
action. Compute is billable while the sandbox runs.

Review the displayed secret metadata. Choose `keep` only when the required
credential exists at the stated scope. Choose `add` only when it is missing.
Enter tokens only at the SBX secret prompt. The block never uses `--force`.
Keep intentional denies. Initial allow rules do not override account denies.
The block does not change account policy or edit an existing sandbox policy.

Context7 needs one browser step. In Docker Agentic Platform, open **MCP**.
Connect Context7 and authorize access with the same Docker account. If it is
not listed, add `https://mcp.context7.com/mcp/oauth` as a remote MCP URL.
Use the connected server name when the block asks for it. This step follows
[Docker's MCP connection instructions](https://docs.docker.com/agentic-platform/mcp/).
Complete this connection before sandbox creation. The block passes the server
name with `--static-mcp`. A sandbox created without an MCP gateway cannot
gain one through `mcp load` on the tested CLI.

Local registrations from `sbx mcp add` do not configure cloud sandbox MCP.
The Console's **Add to your client** command connects an external client.
The user tested that connection; it did not repair the cloud creation error
for the missing `docker` secret. Do not repeat it as a cloud repair step.

Receipts contain no credentials. They are stored under
`%LOCALAPPDATA%\sbx-deploy\cloud`. A completed rerun uses its receipt and
skips CLI calls and file writes. Choose `recheck` to check cloud state again.
Use `recheck` after changing Docker accounts, secrets, or sandbox state.
The receipt does not prove that an expired sandbox still exists.

```powershell
& {
    # Prepare one cloud sandbox. Preserve secrets and policies. Do not deploy.
    $ErrorActionPreference = 'Stop'
    $sandboxName = (Read-Host 'Desired cloud sandbox name').Trim()
    if ($sandboxName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,61}[A-Za-z0-9]$' -or $sandboxName -ieq 'default') { throw 'Use 2-63 ASCII letters, numbers, or hyphens. Start and end with a letter or number. Do not use default.' }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is missing. Run this block in Windows PowerShell.' }
    $stateDirectory = Join-Path $env:LOCALAPPDATA 'sbx-deploy\cloud'
    $statePath = Join-Path $stateDirectory ($sandboxName.ToLowerInvariant() + '.json')
    $connectCommand = "sbx --debug=false --cloud exec -it $sandboxName bash"
    $mutex = [Threading.Mutex]::new($false, ('Local\SBXDeployCloud-' + $sandboxName.ToLowerInvariant()))
    $locked = $false
    try {
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { throw 'Another setup is using this name. Wait for it to finish.' }
        foreach ($path in @((Join-Path $env:LOCALAPPDATA 'sbx-deploy'), $stateDirectory, $statePath)) {
            if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Setup path is a link. Keep it and review ownership: $path" }
        }
        function Ask-Choice([string]$Message, [string[]]$Choices) {
            while ($true) {
                $answer = (Read-Host $Message).Trim().ToLowerInvariant()
                if ($answer -eq 'stop') { throw 'Setup stopped. Keep the receipt and rerun this block to continue.' }
                if ($Choices -contains $answer) { return $answer }
                Write-Host ('Enter ' + ($Choices -join ', ') + ', or stop.')
            }
        }
        function Invoke-Cloud([string[]]$CliArgs) {
            & sbx --debug=false --cloud @CliArgs
            if ($LASTEXITCODE -ne 0) { throw "SBX failed (exit $LASTEXITCODE). Read the error above. Fix the cause and rerun this block. Receipt: $statePath" }
        }
        function Save-Setup {
            $json = $state | ConvertTo-Json -Depth 4
            if ((Test-Path -LiteralPath $statePath) -and ([IO.File]::ReadAllText($statePath) -ceq $json)) { return }
            [IO.Directory]::CreateDirectory($stateDirectory) | Out-Null
            $temporaryPath = Join-Path $stateDirectory ([IO.Path]::GetRandomFileName())
            try {
                [IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($false))
                if (Test-Path -LiteralPath $statePath) { [IO.File]::Replace($temporaryPath, $statePath, [NullString]::Value) } else { [IO.File]::Move($temporaryPath, $statePath) }
            } finally {
                if (Test-Path -LiteralPath $temporaryPath) { Remove-Item -LiteralPath $temporaryPath }
            }
        }
        $state = [pscustomobject]@{ owner = 'sbx-deploy-cloud-setup'; version = 1; name = $sandboxName; prepared = $false; creationPending = $false; created = $false; complete = $false; mcp = 'context7'; network = @() }
        if (Test-Path -LiteralPath $statePath) {
            try { $saved = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { throw "Cannot read receipt. Keep it and review it before repair: $statePath" }
            $expectedKeys = @($state.PSObject.Properties.Name | Sort-Object)
            $savedKeys = @($saved.PSObject.Properties.Name | Sort-Object)
            if (($expectedKeys -join ',') -cne ($savedKeys -join ',') -or $saved.owner -cne $state.owner -or $saved.version -ne 1 -or $saved.name -ine $sandboxName) { throw "Unknown receipt. Keep it and review it before repair: $statePath" }
            foreach ($key in @('prepared', 'creationPending', 'created', 'complete')) { if ($saved.$key -isnot [bool]) { throw "Invalid receipt field $key. Keep and review: $statePath" } }
            if (-not $saved.prepared -or ($saved.created -and -not $saved.creationPending) -or ($saved.complete -and -not $saved.created)) { throw "Invalid receipt progress. Keep and review: $statePath" }
            if ($saved.mcp -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$' -or @($saved.network).Count -eq 0) { throw "Invalid receipt. Keep and review: $statePath" }
            foreach ($target in $saved.network) { if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*:[0-9]{1,5}$') { throw "Invalid network target in receipt. Keep and review: $statePath" } }
            $state = $saved
            if ($state.complete) {
                Write-Host 'Saved host setup is complete. No cloud checks have run.'
                if ((Ask-Choice 'Enter skip to use the receipt, or recheck to query cloud state' @('skip', 'recheck')) -eq 'skip') {
                    Write-Host 'To open sandbox Bash, run this command. Then paste the complete Bash installer:'
                    Write-Host $connectCommand
                    return
                }
                $state.prepared = $false
                $state.complete = $false
            }
        }
        if (-not (Get-Command sbx -CommandType Application -ErrorAction SilentlyContinue)) { throw 'SBX CLI is missing. Install it from https://docs.docker.com/ai/sandboxes/ and reopen PowerShell.' }
        Write-Host '[1/5] Checking cloud access'
        while ($true) {
            $sandboxNames = @(& sbx --debug=false --cloud ls --quiet)
            if ($LASTEXITCODE -eq 0) { break }
            $action = Ask-Choice 'Cloud access failed. Enter login to sign in, or retry after repair' @('login', 'retry')
            if ($action -eq 'login') { Invoke-Cloud @('login') }
        }
        $exists = @($sandboxNames | Where-Object { $_.Trim() -ieq $sandboxName -or $_.Trim() -ieq "opencode/$sandboxName" }).Count -gt 0
        $inspected = $false
        if ($state.created) {
            # A name-list mismatch does not prove that a recorded sandbox is absent.
            try { Invoke-Cloud @('inspect', $sandboxName) } catch { throw "Cannot inspect the recorded sandbox $sandboxName. Keep its receipt and secrets. Check the Docker account and the error above. $($_.Exception.Message)" }
            $exists = $true
            $inspected = $true
        }
        if ($exists -and -not $state.created) {
            if (-not $state.creationPending) { throw 'This sandbox name already exists. Keep it. Use a new name for guided creation, or use the manual steps below for the existing sandbox.' }
            Invoke-Cloud @('inspect', $sandboxName)
            $inspected = $true
            Write-Host 'A prior creation may have finished before its receipt was saved.'
            Ask-Choice 'Check the account, name, and opencode type above. Enter resume only if this is the sandbox you created with this block' @('resume') | Out-Null
            $state.created = $true
            Save-Setup
        }
        Write-Host '[2/5] Preparing cloud credentials'
        if (-not $state.prepared) {
            Invoke-Cloud @('secret', 'ls')
            Write-Host 'OpenAI: keep an existing account credential or a matching sandbox API key. OAuth uses account scope.'
            $openai = Ask-Choice 'OpenAI: enter keep, oauth to add missing account OAuth, or key to add a missing sandbox API key' @('keep', 'oauth', 'key')
            if ($state.created -and $openai -ne 'keep') { throw 'This sandbox already started. Keep it. Set the missing secret with the manual steps below, then test a new named sandbox. Do not replace startup credentials here.' }
            if ($openai -eq 'oauth') { Invoke-Cloud @('secret', 'set', 'openai', '--oauth') }
            if ($openai -eq 'key') { Invoke-Cloud @('secret', 'set', 'openai', '--sandbox', $sandboxName) }
            Write-Host 'GitHub: prefer a token scoped to this sandbox. keep can also use an existing account default.'
            $github = Ask-Choice 'GitHub: enter keep for an existing usable secret, or add for a missing sandbox token' @('keep', 'add')
            if ($state.created -and $github -eq 'add') { throw 'This sandbox already started. Keep it. Prepare the missing GitHub secret with the manual steps below, then test a new named sandbox.' }
            if ($github -eq 'add') { Invoke-Cloud @('secret', 'set', 'github', '--sandbox', $sandboxName) }
            Invoke-Cloud @('secret', 'ls')
            Ask-Choice 'Check secret names and scopes above. Enter ready only when OpenAI and GitHub are configured' @('ready') | Out-Null
            Write-Host '[3/5] Reviewing network access'
            Invoke-Cloud @('policy', 'ls')
            if ($state.created) {
                Invoke-Cloud @('policy', 'ls', $sandboxName)
                Write-Host 'Existing network rules stay unchanged. Check required downloads in the manual section below.'
            } else {
                $state.network = @('chatgpt.com:443', 'auth.openai.com:443', 'api.openai.com:443', 'releases.openai.com:443', 'update.code.visualstudio.com:443', 'vscode.download.prss.microsoft.com:443', 'github.com:443', 'api.github.com:443', 'raw.githubusercontent.com:443', 'release-assets.githubusercontent.com:443', 'opencode.ai:443', 'registry.npmjs.org:443', 'deb.debian.org:80', 'deb.debian.org:443', 'security.debian.org:80', 'security.debian.org:443')
                Write-Host ('Initial sandbox exceptions: ' + ($state.network -join ', '))
                Write-Host 'Agent and kit rules can allow other hosts. Account denies still apply. No account rules will change.'
            }
            Ask-Choice 'Review access and intentional denies. Enter ready to continue' @('ready') | Out-Null
            $state.prepared = $true
            Save-Setup
        } else { Write-Host 'Saved preparation is complete. Credential setup is skipped.' }
        Write-Host '[4/5] Creating or resuming the sandbox'
        if (-not $state.created) {
            Write-Host 'Before creation, connect Context7 under MCP in Docker Agentic Platform. Use the same Docker account.'
            Write-Host 'If needed, add remote URL https://mcp.context7.com/mcp/oauth and authorize access.'
            $serverName = (Read-Host "Connected Context7 server name [Enter for $($state.mcp)]").Trim()
            if ($serverName) {
                if ($serverName -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$') { throw 'Use the connected server name with letters, numbers, periods, underscores, or hyphens.' }
                $state.mcp = $serverName
            }
            Write-Host 'Creation uses 2 CPUs, 4 GiB, a two-hour timeout, and the stop action. Compute is billable.'
            Ask-Choice 'Enter create to create this cloud sandbox' @('create') | Out-Null
            $state.creationPending = $true
            Save-Setup
            $createArgs = @('create', '--name', $sandboxName, '--cpus', '2', '--memory', '4g', '--ttl', '2h', '--on-timeout', 'stop', '--static-mcp', $state.mcp)
            foreach ($target in $state.network) { $createArgs += @('--allow-network', $target) }
            Invoke-Cloud ($createArgs + @('opencode'))
            $state.created = $true
            Save-Setup
        }
        if (-not $inspected) { Invoke-Cloud @('inspect', $sandboxName) }
        Invoke-Cloud @('policy', 'ls', $sandboxName)
        Invoke-Cloud @('exec', $sandboxName, 'bash', '-lc', 'test $(id -un) = agent && command -v bash flock timeout apt-get python3 opencode && sudo -n true')
        Write-Host '[5/5] Connecting Context7'
        Write-Host "Checking connected server: $($state.mcp)"
        # A gateway must be configured at creation. Keep other errors distinct.
        $mcpStatus = & {
            $ErrorActionPreference = 'Continue'
            $lines = @(& sbx --debug=false --cloud mcp ls $sandboxName 2>&1)
            [pscustomobject]@{ code = $LASTEXITCODE; lines = $lines }
        }
        $mcpText = ($mcpStatus.lines | ForEach-Object { $_.ToString() }) -join "`n"
        if ($mcpStatus.code -eq 0) {
            foreach ($line in $mcpStatus.lines) { Write-Host $line }
            $mcpAction = Ask-Choice 'Enter keep if Context7 is already active, or load to attach it' @('keep', 'load')
        } elseif ($mcpText -match '(?m)^\s*(?:not_found:\s*)?sandbox has no MCP gateway\s*$') {
            throw "This sandbox has no MCP gateway. The tested CLI requires --static-mcp at creation. Keep this sandbox, receipt, and secrets. Rerun the updated block with a new sandbox name. Configure its GitHub secret before creation; a secret scoped to this name will not transfer. Receipt: $statePath"
        } else {
            foreach ($line in $mcpStatus.lines) { Write-Host $line }
            throw "MCP status failed (exit $($mcpStatus.code)). Fix the reported error and rerun. Receipt: $statePath"
        }
        if ($mcpAction -eq 'load') { Invoke-Cloud @('mcp', 'load', $state.mcp, '--sandbox', $sandboxName) }
        Invoke-Cloud @('mcp', 'ls', $sandboxName)
        Ask-Choice 'Check that Context7 is active, not skipped. Enter ready to finish, or stop to repair it' @('ready') | Out-Null
        $state.complete = $true
        Save-Setup
        Write-Host 'Host setup is complete. Opening sandbox Bash. Paste the complete sbx_local_opencode_deploy.sh there.'
        Write-Host 'Select cloud in the Bash installer. It will check downloads, credentials, and MCP. Test inference afterward.'
        Invoke-Cloud @('exec', '-it', $sandboxName, 'bash')
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
```

If a command fails, keep the sandbox and receipt. Fix the reported cause and
paste the same block again. A failed SBX command stops setup and reports its
exit code. If creation finished before interruption, the block asks you to
inspect the existing sandbox before it resumes. It never deletes a sandbox.
Do not run two setup blocks for the same name at the same time.

### Creation reports a missing secret named docker

The reported creation failed with `secret not found ... name=docker` after
static MCP was selected. Its credential type and secret store are not yet
confirmed. Do not run `secret set docker`, create a custom token, or change
registry credentials based on this message alone.

Check cloud secret metadata with `sbx --debug=false --cloud secret ls`.
The user completed local gateway registration and sign-in, then confirmed
that the same cloud error remained. This is not a verified repair path.
The missing-secret source remains open. Inspect the resolved published kit
before changing credentials. The user's full v3 descriptor declares no
credentials. The user runs SBX v0.53.0, commit
`2c62838074738845f8f1096ff5f8920df61152fb`. The `docker` reference is outside
this descriptor; generated CLI configuration and cloud provisioning have not
been traced. Local gateway sign-in did not resolve it.

Check account access and cloud connectivity with
`sbx --debug=false --cloud diagnose`. Do not use `--upload` for this check.
If diagnostics pass, send Docker support the CLI version, resolved public
kit descriptor, creation options, and error text. Remove account IDs, private
gateway URLs, and credentials from the report. This is an unresolved cloud
creation failure, not a confirmed missing user-supplied Docker token.

The user ran diagnostics on this setup. All six checks passed. Authentication,
cloud API reachability, cloud entitlement, and TLS checks passed. This does
not confirm that cloud MCP provisioning has all required internal secrets.

Support report:

```text
Title: Cloud creation with --static-mcp fails: secret not found name=docker

Host: Windows PowerShell
CLI: sbx v0.53.0, commit 2c62838074738845f8f1096ff5f8920df61152fb
Workload: docker.io/sbx/opencode:latest
Resolved kit: schemaVersion 3; sandbox image and entrypoint only;
no credential declarations.
Creation options: --static-mcp context7 --cpus 2 --memory 4g
--ttl 2h --on-timeout stop; exact host allow rules also supplied.

Result: Kit configuration fails with:
create cloud sandbox: invalid_argument: secret not found:
account=[redacted] name=docker

Cloud diagnostics: all 6 checks pass. Authentication, API access,
subscription, and TLS checks pass.
OpenAI OAuth exists at account scope.
Local docker-mcp registration and browser sign-in did not fix creation.
Manual controls, outside the PowerShell setup block:
- create --name cloud-test02 --static-mcp context7 opencode: same failure.
- create --name mcp-test01 --static-mcp context7 shell: same failure.
- create --name mcp-test01 shell: succeeds.
All three used sbx --debug=false --cloud.
This isolates the static MCP option. The wrapper, custom network rules,
CPU, memory, and timeout flags are not needed to reproduce the failure.
Console control: Shell with Context7 also fails. Launch preparation reports
one MCP server, then creation reports "MCP servers couldn't be connected."
All failed MCP tests selected Context7. Other MCP servers are not yet tested.
Earlier creation without static MCP succeeded. Its sandbox had no gateway;
mcp load refused attachment and required --static-mcp at creation.

Question: Which component references the docker secret, and what is the
supported way to provision it for CLI cloud MCP without copying tokens
or changing existing credentials?
```

Do not retry creation or change credentials without new evidence.
Do not share tokens, authorization headers,
or private gateway URLs. Keep the receipt and existing secrets. After the
cause is resolved, rerun the block with the same name. It checks for an
existing sandbox before retrying creation.

### Other recovery checks

For a recorded sandbox, setup checks `inspect` by its saved name. A mismatch
in `ls --quiet` output does not establish that the sandbox is absent. If
inspection fails, keep the receipt and secrets. Check the reported CLI error
and Docker account. Setup does not recreate the recorded sandbox.

If the MCP status check reports `sandbox has no MCP gateway`, keep the sandbox,
receipt, and secrets. The user confirmed that `mcp load` cannot add the missing
gateway. Run the updated block with a new sandbox name. Connect Context7 before
creation. The block uses `--static-mcp` to request the gateway. A GitHub secret
scoped to the old name does not transfer. Configure a secret for the new name
at its secret prompt, or use a suitable existing account default. Do not remove
the old sandbox to reuse its name. Other MCP status errors also stop setup.

If a receipt is unknown or damaged, keep it. Inspect the named sandbox and
secret metadata with the manual steps below. Use a new name for a fresh guided
setup. Do not delete secrets, reset policy, or remove a working sandbox to
repair a receipt. The receipt assumes the same Docker account and unchanged
prepared credentials when resuming an incomplete run.

Network rules cover known installer downloads and common Debian sources.
They do not prove connectivity. Image-specific mirrors, redirects, inference,
and VS Code tunnel access can need more hosts. Follow installer errors and
policy logs. Add only missing access. Preserve intentional denies. This block
does not attach a startup kit or publish ports. Cloud Webtop stays disabled.

The commands below are manual recovery steps. Skip completed work after the
guided setup. See [cloud network policy](https://docs.docker.com/ai/sandboxes/cloud/network-policy/)
for account and sandbox scope. Secrets must exist before creation; see
[cloud credentials](https://docs.docker.com/ai/sandboxes/cloud/credentials/).

## Manual creation with a sandbox GitHub token

The user confirmed that this setup works for cloud GitHub access.

For a new sandbox, run these commands in **Windows PowerShell**. Keep existing
sandboxes. Replace `repo-a` with your chosen sandbox name in both commands.
Check existing secrets first with `sbx --cloud secret ls`. Complete any missing
OpenAI setup in section 2 before creating the sandbox.

Store the GitHub token for this sandbox:

```powershell
sbx --cloud secret set github --sandbox repo-a
```

Paste the repository token at the secret prompt. Do not put it in the command.
Then create the sandbox with the same name:

```powershell
sbx --cloud create --name repo-a --static-mcp context7 opencode
```

For another repository, repeat with a different sandbox name and its token.
Connect Context7 in Docker Agentic Platform before creation. Replace `context7`
in the command if its connected server name differs.
A sandbox-scoped GitHub secret overrides the account-scoped GitHub secret.
Use the CLI for these steps. Cloud naming in the TUI is not confirmed.
See [cloud creation](https://docs.docker.com/ai/sandboxes/cloud/usage/#create-a-sandbox)
and [secret scope](https://docs.docker.com/ai/sandboxes/cloud/credentials/#set-credential-scope).
Continue below with the new sandbox name or ID.

## 1. Allow required downloads

In **Windows PowerShell**:

```powershell
sbx --cloud ls
```

Replace `<sandbox-id>` below with the name or ID from this list.

Record the SBX version, image, and expiration time. Allow enough time for
deployment and validation. Collect a report with
[SANDBOX_VALIDATION.md](SANDBOX_VALIDATION.md) before deployment.

In **Windows PowerShell**, inspect account and sandbox rules:

```powershell
sbx --cloud policy ls
```

```powershell
sbx --cloud policy ls <sandbox-id>
```

Skip this step if all four hosts are already allowed. Keep intentional denies.
Do not add an allow rule for a target covered by an intentional deny. The
cloud CLI can replace an exact deny with an allow in the same scope.
For missing Codex or VS Code download access, add a sandbox-scoped rule in
**Windows PowerShell**:

```powershell
sbx --cloud policy allow network "chatgpt.com:443,releases.openai.com:443,update.code.visualstudio.com:443,vscode.download.prss.microsoft.com:443" --sandbox <sandbox-id>
```

## 2. Check cloud credentials

Cloud secrets are separate from local secrets and Docker Agentic Platform
secrets. Local Windows bindings do not configure cloud credentials.

Check metadata before adding credentials:

```powershell
sbx --cloud secret ls
```

If OpenAI OAuth is missing, complete browser sign-in:

```powershell
sbx --cloud secret set openai --oauth
```

Cloud OpenAI OAuth uses account scope. For an API key instead, use
`sbx --cloud secret set openai`. Do not replace an existing credential unless
you intend to change it.

For a separate GitHub token per sandbox, use the steps at the top of this file.
Only if you want an account-wide GitHub default and it is missing, run:

```powershell
sbx --cloud secret set github
```

Enter the token at the secret prompt. Do not put it in shell commands, files,
or shared output. Cloud secrets do not support the local `--command` resolver.
Configure credentials before creating a new sandbox. For an existing sandbox,
check that its startup credentials are available before deployment.

The installer preserves cloud startup credentials and saved logins. With
`SBX_CRED_OPENAI_MODE=oauth`, it configures both harnesses with shared proxy
placeholders. Cloud OpenCode does not need the local OAuth bridge file.
Its managed OAuth entry uses a fixed future expiry because the cloud proxy
refreshes real tokens. The installer preserves other active logins and an
inactive managed login. It stops if its credential ID contains different
tokens. The user confirmed inference with these placeholders in OpenCode
v2.3.0 after a background service restart. Deployment restarts the cloud
OpenCode service once for the managed OAuth entry. Save work before deployment;
restart can interrupt OpenCode sessions. A success receipt prevents repeat
restarts on unchanged runs. A failed or interrupted restart is retried.
The full installer path and unchanged reruns still need sandbox checks.

### OpenAI HTTP 401 with a stored OAuth secret

An `oauth_refresh` entry confirms that the host has an OAuth secret. It does
not confirm access from an existing sandbox. Docker requires credential setup
before sandbox launch. Keep the existing secret and saved logins.

The credential helper can report `API key` when it selects `OPENAI_API_KEY`.
This label does not confirm that the value is a real API key. The helper tests
`https://api.openai.com/v1/models` for this source. A cloud placeholder can need
a different OAuth route. Confirm the route before changing configuration.

In **sandbox Bash**, print only the advertised mode and key presence:

```bash
printf 'OpenAI mode: %s; OPENAI_API_KEY: %s\n' "${SBX_CRED_OPENAI_MODE:-unset}" "${OPENAI_API_KEY:+set}"
```

An empty key-presence field means the variable is empty or unset. Do not print
the key or auth files. Check a model response in OpenCode and Codex. Record
whether each response works and whether the sandbox started before the secret
was stored. A model-list failure alone does not establish an inference failure.

### GitHub HTTP 401

The helper tests GitHub account access with `gh api user`. `Host proxy` means
it found a proxy placeholder. This label does not confirm a valid cloud secret.
A 401 does not identify the cause. OpenAI access uses a separate credential.

For a sandbox created with the CLI, check metadata in **Windows PowerShell**:

```powershell
sbx --cloud secret ls
```

Check the GitHub entry and its scope. A sandbox-scoped secret takes precedence
over an account-scoped secret. A local secret or Windows GitHub login does not
configure cloud access. If the cloud GitHub secret is missing:

```powershell
sbx --cloud secret set github
```

Enter a valid GitHub token at the prompt. If an entry exists, check its scope
and token validity before replacing it. Do not share the token or auth files.
For a sandbox created in the web UI, check its Docker Agentic Platform secrets.
The CLI cloud store does not supply that interface.

Repeat `check_credentials` in **sandbox Bash**. Docker requires secrets before
sandbox launch. If access still fails, record whether the sandbox started before
the secret was set. Keep the existing sandbox and saved logins. Test a disposable
new sandbox after secret setup to check startup access. Do not reset the working
sandbox or restart the local daemon to repair cloud access.

### OpenCode reports missing scope `api.responses.write`

The user confirmed this recovery in a fresh cloud sandbox:

1. In OpenCode, open `/connect` and select **OpenAI**.
2. Select **Codex device code (legacy)**.
3. Complete browser sign-in with the ChatGPT subscription account.
4. Start a new chat and ask `Reply with OK only.`

This explicit OAuth login produced a model response. An API key is not required
for this tested path. Keep the saved login. Interactive sign-in can store real
credentials inside the sandbox; remove them before saving or moving a template,
as Docker directs. Do not share auth files or authentication headers.

The user also confirmed a stale background service after placeholder import:
standalone inference passed, normal inference failed, and normal inference
passed after the service restart. In sandbox Bash, save work, then run:

```bash
opencode service restart
```

Retry the same model. A passing `check_credentials --openai` tests direct
model-list access, not OpenCode inference or its live endpoint. Do not change
account roles based on this error alone.

## 3. Connect MCP

Connect Context7 through Docker Agentic Platform with the same Docker account.
Cloud sandboxes do not use registrations from local `sbx mcp add`.
Select the connected server at creation with `--static-mcp context7`.
The tested CLI cannot add a gateway later to a sandbox created without one.

Check the cloud sandbox gateway:

```powershell
sbx --cloud mcp ls <sandbox-id>
```

If the gateway exists, load Context7 only if absent. Use its connected server
name if different. If no gateway exists, use the Windows setup block with a
new sandbox name. Preserve the old sandbox and its secrets.

```powershell
sbx --cloud mcp load context7 --sandbox <sandbox-id>
```

The installer uses `SBX_MCP_GATEWAY_URL` or `MCP_GATEWAY_URL` if set. Otherwise,
it reuses its saved URL or reads the existing `mcp-gateway` entry in OpenCode,
then Codex. OpenCode JSONC takes precedence over JSON. Discovery reads no auth
files and copies no authentication headers. It makes no network requests.

If no endpoint exists, tool setup continues and reports MCP as pending. It
does not create an empty MCP entry or guess the local gateway address. Attach
the server, then rerun. If automatic discovery still finds no URL, review the
agent MCP config locally. Do not share its full contents or authentication headers.

Set the URL in **sandbox Bash**, only if needed. Replace the example value:

```bash
export SBX_MCP_GATEWAY_URL='<sandbox-mcp-url>'
```

Use an HTTP or HTTPS URL without credentials, a query string, or a fragment.
Both harnesses use this endpoint. Existing MCP headers and user overrides stay.
Do not put an access token in the URL. No cloud endpoint is verified by this
repository yet. Existing headers stay in their original harness. If cloud
MCP requires authentication, its equivalent Codex setup still needs validation.

## 4. Deploy and check

Paste into **sandbox Bash**. After the logo, always confirm the environment.
Press Enter to accept the displayed default, or type `local` or `cloud`.
The installer offers cloud mode when the hostname
matches `sbx-` plus 27 lowercase letters or digits, and local sandbox ID and
agent variables are absent. Credential modes do not select the environment.
These markers match the supplied
cloud report. If signals are incomplete or conflict, type the environment.
To set the prompt default before the paste, use:

```bash
export SBX_ENV=cloud
```

Paste the complete `sbx_local_opencode_deploy.sh`. It remains one editable file.
No build step or extra deployment files are required. Check the environment row.
Wait for setup to finish. If a download fails, follow the printed recovery
commands, then rerun:

```bash
bash ~/sbx_local_opencode_deploy.sh
```

After successful setup, check credentials and MCP:

```bash
check_credentials
```

```bash
check_mcp
```

The installer saves the environment and MCP URL through its ownership checks.
The default record is `~/.local/state/sbx-deploy/environment`. Automatic
selection can reuse it only for the same hostname. `SBX_ENV` sets the default
before saved and detected settings. Every run still asks for confirmation.
Detection uses the reported combinations; it is not a universal guarantee for
other images. A terminal is required, including when `SBX_ENV` is set.

If setup stopped before saving the record, keep the environment exports set.
If ownership is unknown, preserve the record and its reported baseline.
Review both before repair. Do not delete saved logins.

Check a model response and an MCP tool in OpenCode and Codex. Cloud credential
checks cover selected OpenAI credentials in both harnesses. Model-list access
does not prove inference. Repeat cached checks with:

```bash
SBX_CHECK_AUTH=1 bash ~/sbx_local_opencode_deploy.sh
```

For authentication failures, check cloud secret scope and startup setup.
Do not restart the local daemon to repair cloud access. Interactive harness
sign-in is optional. It writes credentials inside the sandbox. Remove those
credentials before saving a template or moving the sandbox, as Docker directs.

## Supported differences and remaining checks

- Shared models, subagents, tools, shell, tmux, logs, and ownership rules apply
  to both environments. The installer needs a Debian-compatible image, Bash,
  `flock`, and passwordless sudo.
- Cloud OpenCode uses managed OAuth placeholders when OAuth mode is
  advertised. It creates no local bridge file. Startup credentials and
  saved selections stay. Confirm authentication and inference in both harnesses.
- Webtop deployment is disabled in cloud mode. Existing containers stay.
  Cloud port publication creates a public URL. Do not expose the default
  desktop without authentication.
- Run `vscode_tunnel` for remote access and after each cloud restart. Use the
  printed URL and device code if browser forwarding is absent. Cloud tunnel
  operation and startup-kit attachment still need validation.
- Cloud sandboxes have no Windows workspace mount. Transfer files or clone
  a repository inside the sandbox.
- Complete fresh install, unchanged rerun, upgrade and preservation,
  interruption, reconnect, and both harness checks. An unchanged successful
  rerun must skip installs, network calls, config writes, and new backups.

## Sources

- [Cloud credentials](https://docs.docker.com/ai/sandboxes/cloud/credentials/)
- [Cloud commands and MCP setup](https://docs.docker.com/ai/sandboxes/cloud/usage/)
- [Local and cloud differences](https://docs.docker.com/ai/sandboxes/cloud/local-vs-cloud/)
