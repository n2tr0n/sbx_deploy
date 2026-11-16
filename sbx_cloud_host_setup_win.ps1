& {
    # Prepare one cloud sandbox. Preserve secrets and policies. Do not deploy.
    # Show the SBX banner, stage rows, and numbered menus. Use NO_COLOR for plain output.
    # Read single keys in a console. Use line input when single-key input is unavailable.
    $ErrorActionPreference = 'Stop'
    $setupWidth = 80
    try { if ($Host.UI.RawUI.WindowSize.Width -gt 0) { $setupWidth = [Math]::Min(80, $Host.UI.RawUI.WindowSize.Width) } } catch { }
    if ($env:COLUMNS -match '^[1-9][0-9]{0,2}$') { $setupWidth = [Math]::Min($setupWidth, [int]$env:COLUMNS) }
    $setupColor = -not (Test-Path Env:NO_COLOR) -and $env:TERM -ne 'dumb' -and -not [Console]::IsOutputRedirected
    function Write-SetupLine([string]$Text = '', [ConsoleColor]$Color = 'Gray') {
        if ($setupColor) { Write-Host $Text -ForegroundColor $Color } else { Write-Host $Text }
    }
    function Show-SetupCard([string]$Title, [string[]]$Lines) {
        Write-SetupLine
        if ($setupWidth -ge 60) { Write-SetupLine ('  +' + ('-' * ($setupWidth - 6)) + '+') 'DarkGray' }
        $rows = @($Title) + $Lines
        for ($row = 0; $row -lt $rows.Count; $row++) {
            $color = 'Gray'
            if ($row -eq 0) { $color = 'Green' }
            $line = $rows[$row]
            if ($setupWidth -ge 60 -and $line.Length -le ($setupWidth - 8)) {
                Write-SetupLine ('  | ' + $line.PadRight($setupWidth - 8) + ' |') $color
            } else { Write-SetupLine "  $line" $color }
        }
        if ($setupWidth -ge 60) { Write-SetupLine ('  +' + ('-' * ($setupWidth - 6)) + '+') 'DarkGray' }
    }
    function Write-SetupStage([string]$Name, [string]$Status, [string]$Detail) {
        $color = switch ($Status) { 'OK' { 'Green' } 'SKIP' { 'DarkGray' } default { 'Yellow' } }
        if ($setupWidth -ge 60) { Write-SetupLine ('  {0,-18} | {1,-7} | {2}' -f $Name, $Status, $Detail) $color } else { Write-SetupLine "  $Name [$Status] $Detail" $color }
    }
    function Stop-Setup {
        throw [OperationCanceledException]::new('Setup cancelled. Completed work is kept. Rerun this script to continue.')
    }
    function Read-SetupKey([string]$Prompt) {
        # Use line input when the host cannot read individual keys.
        if ([Console]::IsInputRedirected -or $env:TERM -eq 'dumb' -or $Host.Name -ne 'ConsoleHost') {
            return (Read-Host "  $Prompt").Trim().ToLowerInvariant()
        }
        if ($setupColor) { Write-Host "  $Prompt " -NoNewline -ForegroundColor Green } else { Write-Host "  $Prompt " -NoNewline }
        $key = [Console]::ReadKey($true)
        Write-Host
        switch ($key.Key) {
            'Escape' { return ([string][char]27) }
            'Enter' { return '' }
            default { return $key.KeyChar.ToString().ToLowerInvariant() }
        }
    }
    function Confirm-Setup([string]$Message, [switch]$RequireYes) {
        Write-SetupLine
        Write-SetupLine "  $Message" 'Yellow'
        while ($true) {
            $prompt = '[Enter] Continue  [Esc/0] Cancel'
            if ($RequireYes) { $prompt = '[y/N]  [Esc/0] Cancel' }
            $answer = Read-SetupKey $prompt
            if ($answer -in @(([string][char]27), '0', 'n') -or ($RequireYes -and $answer -eq '')) { Stop-Setup }
            if ($answer -eq 'y' -or (-not $RequireYes -and $answer -eq '')) { return }
            Write-SetupLine '  Use the displayed keys.' 'Yellow'
        }
    }
    function Ask-Choice([string]$Message, [string[]]$Choices, [string[]]$Labels, [int]$Default = 0) {
        Write-SetupLine
        Write-SetupLine "  $Message" 'Green'
        for ($index = 0; $index -lt $Choices.Count; $index++) {
            $suffix = ''
            if ($Default -eq ($index + 1)) { $suffix = ' (default)' }
            Write-SetupLine ('    {0}. {1}{2}' -f ($index + 1), $Labels[$index], $suffix)
        }
        while ($true) {
            $prompt = "Select 1-$($Choices.Count)  [Esc/0] Cancel"
            if ($Default -gt 0) { $prompt += "  [Enter] $Default" }
            $answer = Read-SetupKey $prompt
            if ($answer -in @(([string][char]27), '0')) { Stop-Setup }
            if ($answer -eq '' -and $Default -gt 0) { return $Choices[$Default - 1] }
            if ($answer -match '^[1-9]$' -and [int]$answer -le $Choices.Count) { return $Choices[[int]$answer - 1] }
            Write-SetupLine "  Choose a number from 1 to $($Choices.Count)." 'Yellow'
        }
    }
    if ($setupWidth -ge 78) {
        $banner = @'
  .-----------------------------------------------------------------------.
 /__________  N i T R O N   P R E S E N T S  ______________________________\
 \_  _                                                                 _  _/
   \/     _______   _______ ___   ___                                   \/
   /\    /  _____/ /  __   \\  \ /  /                                   /\
  /  \   \____  \ /  /_/  <  \  V  /    .:: S B X   D E P L O Y ::.    /  \
  \  /   -----/ //  /_/   /  /  \  \                                   \  /
   \/  /_______//________/__/__/_\__\_________________________________  \/
   /\  \__  Windows cloud setup                                  __/  /\
 _/  \____\_______________________________________________________/____/  \_
 \_________________________________________________________________________/
'@
        foreach ($line in ($banner -split '\r?\n')) { Write-SetupLine $line 'Green' }
    } else {
        Write-SetupLine '  N i T R O N   P R E S E N T S' 'DarkGray'
        Write-SetupLine '  S B X   D E P L O Y' 'Green'
        Write-SetupLine '  Windows cloud setup' 'DarkGray'
    }
    Write-SetupLine
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
            Show-SetupCard "ADD $($Service.ToUpperInvariant()) SECRET" @('Paste the key or token at the masked prompt.', 'Input shows *. Press Enter when done.')
            $secret = Read-Host -Prompt "$Service secret" -AsSecureString
            try {
                if ($secret.Length -eq 0) { throw 'Secret input is empty. Nothing was saved.' }
                Write-SetupLine '  Input received. Saving secret...' 'Yellow'
                if ($Service -eq 'context7') {
                    Invoke-Cloud @('secret', 'set-custom', '--name', 'context7', '--host', 'mcp.context7.com', '--env', 'CONTEXT7_API_KEY', '--header', 'Authorization', '--format', 'Bearer %s', '--value-stdin') -Secret $secret
                } else {
                    Invoke-Cloud @('secret', 'set', $Service, '--sandbox', $sandboxName) -Secret $secret
                }
                Write-SetupLine '  Secret saved.' 'Green'
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
        $state = [pscustomobject]@{ owner = 'sbx-deploy-cloud-setup'; version = 2; name = $sandboxName; prepared = $false; creationPending = $false; created = $false; complete = $false; mcp = 'context7'; network = @() }
        if (Test-Path -LiteralPath $statePath) {
            try { $saved = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch { throw "Cannot read receipt. Keep it and review it before repair: $statePath" }
            $expectedKeys = @($state.PSObject.Properties.Name | Sort-Object)
            $savedKeys = @($saved.PSObject.Properties.Name | Sort-Object)
            if (($expectedKeys -join ',') -cne ($savedKeys -join ',') -or $saved.owner -cne $state.owner -or $saved.version -notin @(1, 2) -or $saved.name -ine $sandboxName) { throw "Unknown receipt. Keep it and review it before repair: $statePath" }
            foreach ($key in @('prepared', 'creationPending', 'created', 'complete')) { if ($saved.$key -isnot [bool]) { throw "Invalid receipt field $key. Keep and review: $statePath" } }
            if (-not $saved.prepared -or ($saved.created -and -not $saved.creationPending) -or ($saved.complete -and -not $saved.created)) { throw "Invalid receipt progress. Keep and review: $statePath" }
            if ($saved.mcp -notmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*$' -or @($saved.network).Count -eq 0) { throw "Invalid receipt. Keep and review: $statePath" }
            foreach ($target in $saved.network) { if ($target -notmatch '^[A-Za-z0-9][A-Za-z0-9.-]*:[0-9]{1,5}$') { throw "Invalid network target in receipt. Keep and review: $statePath" } }
            $state = $saved
            if ($state.version -eq 1) {
                Show-SetupCard 'UPDATE HOST PREPARATION' @('This setup now uses direct Context7 connections.', 'Review the global cloud Context7 key before continuing.')
                $state.version = 2
                $state.prepared = $false
                $state.complete = $false
                $state.mcp = 'context7'
            }
            if ($state.complete) {
                Show-SetupCard 'SAVED SETUP FOUND' @("Sandbox: $sandboxName", 'Host setup is complete. No cloud checks have run.')
                if ((Ask-Choice 'Saved host setup' @('skip', 'recheck') @('Use the receipt; skip cloud checks', 'Recheck cloud state') 1) -eq 'skip') {
                    Show-SetupCard 'READY TO CONNECT' @('Run this command, then paste the complete Bash installer:')
                    Write-SetupLine $connectCommand 'Green'
                    return
                }
                $state.prepared = $false
                $state.complete = $false
            }
        }
        if (-not (Get-Command sbx -CommandType Application -ErrorAction SilentlyContinue)) { throw 'SBX CLI is missing. Install it from https://docs.docker.com/ai/sandboxes/ and reopen PowerShell.' }
        Show-SetupCard 'CLOUD HOST SETUP' @("Sandbox: $sandboxName", 'Profile: cloud / opencode', '1 Access  2 Credentials  3 Network  4 Sandbox  5 MCP')
        Write-SetupStage 'Cloud access' 'RUN' 'Checking account and sandbox'
        while ($true) {
            $sandboxNames = @(& sbx --debug=false --cloud ls --quiet)
            if ($LASTEXITCODE -eq 0) { break }
            $action = Ask-Choice 'Cloud access failed' @('login', 'retry') @('Sign in to Docker', 'Retry after repair')
            if ($action -eq 'login') { Invoke-Cloud @('login') }
        }
        $exists = @($sandboxNames | Where-Object { $_.Trim() -ieq $sandboxName -or $_.Trim() -ieq "opencode/$sandboxName" }).Count -gt 0
        $inspected = $false
        if ($state.created) {
            # A name-list mismatch does not prove that a recorded sandbox is absent.
            $inspection = & {
                $ErrorActionPreference = 'Continue'
                $lines = @(& sbx --debug=false --cloud inspect $sandboxName 2>&1)
                [pscustomobject]@{ code = $LASTEXITCODE; lines = $lines }
            }
            foreach ($line in $inspection.lines) { Write-SetupLine $line.ToString() }
            $inspectionText = ($inspection.lines | ForEach-Object { $_.ToString() }) -join "`n"
            $missingPattern = "(?m)^\s*(?:error:\s*)?sandbox '(?:opencode/)?" + [regex]::Escape($sandboxName) + "' not found\s*$"
            if ($inspection.code -eq 0) {
                $exists = $true
                $inspected = $true
            } elseif (-not $exists -and $inspectionText -match $missingPattern) {
                Show-SetupCard 'RECORDED SANDBOX IS MISSING' @("Name: $sandboxName", 'Docker lists no matching sandbox in this account.', 'Check that you are using the intended Docker account.', 'Existing cloud secrets and host logins will stay.', 'A new sandbox with this name needs a fresh setup review.')
                Confirm-Setup 'Recreate this sandbox name using the current Docker account?' -RequireYes
                # Do not write the reset until credential and network review succeeds.
                $state.created = $false
                $state.creationPending = $false
                $state.prepared = $false
                $state.complete = $false
            } else {
                throw "Cannot inspect the recorded sandbox $sandboxName (exit $($inspection.code)). Keep its receipt and secrets. Check the Docker account and the error above. Recreation is available only when both listing and inspection confirm absence. Receipt: $statePath"
            }
        }
        if ($exists -and -not $state.created) {
            if (-not $state.creationPending) { throw 'This sandbox name already exists. Keep it. Use a new name for guided creation, or use the manual steps below for the existing sandbox.' }
            Invoke-Cloud @('inspect', $sandboxName)
            $inspected = $true
            Write-SetupLine '  A prior creation may have finished before its receipt was saved.' 'Yellow'
            Confirm-Setup 'Does the account, name, and opencode type match the sandbox you created?' -RequireYes
            $state.created = $true
            Save-Setup
        }
        Write-SetupStage 'Cloud access' 'OK' 'Account and sandbox checked'
        Write-SetupStage 'Credentials' 'RUN' 'Reviewing secret metadata'
        if (-not $state.prepared) {
            Invoke-Cloud @('secret', 'ls')
            Write-SetupLine '  OpenAI OAuth uses account scope. API keys can use sandbox scope.'
            $openai = Ask-Choice 'OpenAI authentication' @('keep', 'oauth', 'key') @('Keep an existing usable credential', 'Add missing account OAuth (browser sign-in)', 'Add a missing sandbox API key')
            if ($state.created -and $openai -ne 'keep') { throw 'This sandbox already started. Keep it. Set the missing secret with the manual steps below, then test a new named sandbox. Do not replace startup credentials here.' }
            if ($openai -eq 'oauth') { Invoke-Cloud @('secret', 'set', 'openai', '--oauth') }
            if ($openai -eq 'key') { Set-CloudSecret 'openai' }
            Write-SetupLine '  Prefer a GitHub token for this sandbox. An account default can also apply.'
            $github = Ask-Choice 'GitHub authentication' @('keep', 'add') @('Keep an existing usable secret', 'Add a missing sandbox token')
            if ($state.created -and $github -eq 'add') { throw 'This sandbox already started. Keep it. Prepare the missing GitHub secret with the manual steps below, then test a new named sandbox.' }
            if ($github -eq 'add') { Set-CloudSecret 'github' }
            Write-SetupLine '  Context7 uses a global cloud key. The cloud proxy adds the key to requests.'
            $context7 = Ask-Choice 'Context7 global API key' @('keep', 'add') @('Keep the existing global cloud custom secret', 'Add a missing global Context7 API key')
            if ($state.created -and $context7 -eq 'add') { throw 'This sandbox already started. Prepare the global Context7 key, then create a fresh named sandbox so its startup includes the custom secret.' }
            if ($context7 -eq 'add') { Set-CloudSecret 'context7' }
            Invoke-Cloud @('secret', 'ls')
            Confirm-Setup 'Check OpenAI and GitHub scope, and the global Context7 host, environment, and Bearer header.'
            Write-SetupStage 'Credentials' 'OK' 'Secret metadata confirmed'
            Write-SetupStage 'Network access' 'RUN' 'Reviewing policy'
            Invoke-Cloud @('policy', 'ls')
            if ($state.created) {
                Invoke-Cloud @('policy', 'ls', $sandboxName)
                Write-SetupLine '  Existing network rules stay. See HOST_SETUP_CLOUD.md for download checks.'
            } else {
                $state.network = @('mcp.context7.com:443', 'chatgpt.com:443', 'auth.openai.com:443', 'api.openai.com:443', 'releases.openai.com:443', 'update.code.visualstudio.com:443', 'vscode.download.prss.microsoft.com:443', 'github.com:443', 'api.github.com:443', 'raw.githubusercontent.com:443', 'release-assets.githubusercontent.com:443', 'opencode.ai:443', 'registry.npmjs.org:443', 'deb.debian.org:80', 'deb.debian.org:443', 'security.debian.org:80', 'security.debian.org:443')
                Show-SetupCard 'INITIAL NETWORK EXCEPTIONS' $state.network
                Write-SetupLine '  Agent and kit rules can allow other hosts. Account denies still apply.'
            }
            Confirm-Setup 'Check network access and keep intentional denies.'
            $state.prepared = $true
            Save-Setup
            Write-SetupStage 'Network access' 'OK' 'Policy review saved'
        } else {
            Write-SetupStage 'Credentials' 'SKIP' 'Preparation already saved'
            Write-SetupStage 'Network access' 'SKIP' 'Preparation already saved'
        }
        Write-SetupStage 'Sandbox' 'RUN' 'Creating or resuming'
        if (-not $state.created) {
            Show-SetupCard 'CREATE CLOUD SANDBOX' @("Name: $sandboxName", 'Agent: opencode', 'Context7: direct / global cloud API key', 'Compute: 2 CPUs / 4 GiB', 'Timeout: 2 hours / stop', 'Compute is billable while running.')
            Confirm-Setup 'Create this cloud sandbox?' -RequireYes
            $state.creationPending = $true
            Save-Setup
            $createArgs = @('create', '--name', $sandboxName, '--cpus', '2', '--memory', '4g', '--ttl', '2h', '--on-timeout', 'stop')
            foreach ($target in $state.network) { $createArgs += @('--allow-network', $target) }
            Invoke-Cloud ($createArgs + @('opencode'))
            $state.created = $true
            Save-Setup
        }
        if (-not $inspected) { Invoke-Cloud @('inspect', $sandboxName) }
        Invoke-Cloud @('policy', 'ls', $sandboxName)
        Invoke-Cloud @('exec', $sandboxName, 'bash', '-lc', 'test $(id -un) = agent && command -v bash flock timeout apt-get python3 opencode && sudo -n true')
        Write-SetupStage 'Sandbox' 'OK' 'Runtime prerequisites checked'
        Write-SetupStage 'Context7 key' 'RUN' 'Checking startup placeholder'
        Write-SetupLine '  Checking key presence only. The Bash installer configures both MCP clients.'
        try { Invoke-Cloud @('exec', $sandboxName, 'bash', '-lc', 'test ${CONTEXT7_API_KEY:+set}x = setx') } catch { throw "Context7 startup check failed. Check the global custom secret host mcp.context7.com, environment CONTEXT7_API_KEY, and Authorization Bearer format. If this sandbox started before the secret existed, create a fresh sandbox. Keep host logins and secrets. $($_.Exception.Message)" }
        Confirm-Setup 'Global cloud key preparation is complete. Continue to the Bash installer?'
        $state.complete = $true
        Save-Setup
        Write-SetupStage 'Context7 key' 'OK' 'Placeholder present; tool checks follow deployment'
        Show-SetupCard 'HOST SETUP COMPLETE' @("Sandbox: $sandboxName", 'Opening sandbox Bash.', 'Paste the complete sbx_local_opencode_deploy.sh.', 'Select cloud in the Bash installer.', 'Then check credentials, MCP tools, and model inference.')
        Invoke-Cloud @('exec', '-it', $sandboxName, 'bash')
    } finally {
        if ($locked) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
