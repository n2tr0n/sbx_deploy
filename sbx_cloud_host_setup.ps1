& {
    # Prepare one cloud sandbox. Preserve secrets and policies. Do not deploy.
    $ErrorActionPreference = 'Stop'
    $sandboxName = (Read-Host 'Desired cloud sandbox name').Trim()
    if ($sandboxName -notmatch '^[A-Za-z0-9][A-Za-z0-9-]{0,61}[A-Za-z0-9]$' -or $sandboxName -ieq 'default') { throw 'Use 2-63 ASCII letters, numbers, or hyphens. Start and end with a letter or number. Do not use default.' }
    if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is missing. Run this script in Windows PowerShell.' }
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
                if ($answer -eq 'stop') { throw 'Setup stopped. Keep the receipt and rerun this script to continue.' }
                if ($Choices -contains $answer) { return $answer }
                Write-Host ('Enter ' + ($Choices -join ', ') + ', or stop.')
            }
        }
        function Invoke-Cloud([string[]]$CliArgs, [Security.SecureString]$Secret) {
            if ($null -eq $Secret) {
                & sbx --debug=false --cloud @CliArgs
            } else {
                $secretPointer = [IntPtr]::Zero
                try {
                    $secretPointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secret)
                    # Send the value through stdin. Never put it in arguments or files.
                    [Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer) | & sbx --debug=false --cloud @CliArgs
                } finally {
                    if ($secretPointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer) }
                }
            }
            if ($LASTEXITCODE -ne 0) { throw "SBX failed (exit $LASTEXITCODE). Read the error above. Fix the cause and rerun this script. Receipt: $statePath" }
        }
        function Set-CloudSecret([string]$Service) {
            Write-Host "Paste the $Service key or token. Input is masked with *. Press Enter when done."
            $secret = Read-Host -Prompt "$Service secret" -AsSecureString
            try {
                if ($secret.Length -eq 0) { throw 'Secret input is empty. Nothing was saved.' }
                Write-Host 'Input received. Saving secret...'
                Invoke-Cloud @('secret', 'set', $Service, '--sandbox', $sandboxName) -Secret $secret
                Write-Host 'Secret saved.'
            } finally {
                $secret.Dispose()
            }
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
            Ask-Choice 'Check the account, name, and opencode type above. Enter resume only if this is the sandbox you created with this script' @('resume') | Out-Null
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
            if ($openai -eq 'key') { Set-CloudSecret 'openai' }
            Write-Host 'GitHub: prefer a token scoped to this sandbox. keep can also use an existing account default.'
            $github = Ask-Choice 'GitHub: enter keep for an existing usable secret, or add for a missing sandbox token' @('keep', 'add')
            if ($state.created -and $github -eq 'add') { throw 'This sandbox already started. Keep it. Prepare the missing GitHub secret with the manual steps below, then test a new named sandbox.' }
            if ($github -eq 'add') { Set-CloudSecret 'github' }
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
            throw "This sandbox has no MCP gateway. The tested CLI requires --static-mcp at creation. Keep this sandbox, receipt, and secrets. Rerun the updated script with a new sandbox name. Configure its GitHub secret before creation; a secret scoped to this name will not transfer. Receipt: $statePath"
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
