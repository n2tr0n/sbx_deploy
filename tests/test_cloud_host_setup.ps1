# Test the documented block with fake CLI calls. Do not contact Docker.
& {
$ErrorActionPreference = 'Stop'
$guidePath = Join-Path $PSScriptRoot '..\HOST_SETUP_CLOUD.md'
$guide = Get-Content -LiteralPath $guidePath -Raw
$match = [regex]::Match($guide, '(?s)```powershell\r?\n(.*?)\r?\n```')
if (-not $match.Success) { throw 'The setup block is missing.' }
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($match.Groups[1].Value, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$setupBlock = $ast.GetScriptBlock()
$originalLocalAppData = $env:LOCALAPPDATA
$testDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) ('.cloud-setup-test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testDirectory) | Out-Null
$script:calls = [Collections.Generic.List[string]]::new()
$script:answers = [Collections.Generic.Queue[string]]::new()
$script:existingNames = @()
$script:quietNames = $null
$script:failCommand = ''
$script:createThenFail = $false
$script:mcpNoGateway = $false
$script:mcpStatusError = ''

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Read-Host([string]$Prompt) {
    if (-not $script:answers.Count) { throw "No test answer for: $Prompt" }
    return $script:answers.Dequeue()
}
function Get-Command {
    # The guide requires an installed CLI. Supply that prerequisite for tests.
    return [pscustomobject]@{ Name = 'sbx'; CommandType = 'Application' }
}
function sbx {
    $command = @($args) -join ' '
    $script:calls.Add($command)
    $global:LASTEXITCODE = 0
    if ($command -like '* create *' -and $script:createThenFail) {
        $script:existingNames = @('cloud-test')
        $global:LASTEXITCODE = 7
        return
    }
    if ($script:failCommand -and $command -like $script:failCommand) { $global:LASTEXITCODE = 9; return }
    if ($command -like '* mcp ls *' -and ($script:mcpNoGateway -or $script:mcpStatusError)) {
        $message = $script:mcpStatusError
        if ($script:mcpNoGateway) { $message = "error: sbxcloud: not found`n        not_found: sandbox has no MCP gateway" }
        Write-Error $message
        $global:LASTEXITCODE = 1
        return
    }
    if ($command -like '* mcp load *') { $script:mcpNoGateway = $false }
    if ($command -like '* ls --quiet') {
        if ($null -ne $script:quietNames) { $script:quietNames } else { $script:existingNames }
        return
    }
    if ($command -like '* inspect cloud-test' -and $script:existingNames -notcontains 'cloud-test') { 'not_found: sandbox not found'; $global:LASTEXITCODE = 1; return }
    if ($command -like '* policy ls*') { 'Account deny remains: intentional.example:443'; return }
    if ($command -like '* create *') { $script:existingNames = @('cloud-test') }
}
function Run-Setup([string[]]$Replies, [string]$ExpectedError = '') {
    $script:answers.Clear()
    foreach ($reply in $Replies) { $script:answers.Enqueue($reply) }
    $caught = ''
    try { & $setupBlock | Out-Null } catch { $caught = $_.Exception.Message }
    if ($ExpectedError) { Assert-True ($caught -like $ExpectedError) "Expected '$ExpectedError', got '$caught'." } else { Assert-True (-not $caught) "Unexpected error: $caught" }
    Assert-True ($script:answers.Count -eq 0) 'The setup skipped a required test answer.'
}
function Start-Case([string]$Name) {
    $env:LOCALAPPDATA = Join-Path $testDirectory $Name
    $script:calls.Clear()
    $script:existingNames = @()
    $script:quietNames = $null
    $script:failCommand = ''
    $script:createThenFail = $false
    $script:mcpNoGateway = $false
    $script:mcpStatusError = ''
}
function Receipt-Path { return (Join-Path $env:LOCALAPPDATA 'sbx-deploy\cloud\cloud-test.json') }
try {
    Start-Case 'fresh'
    Run-Setup @('cloud-test', 'oauth', 'add', 'ready', 'ready', '', 'create', 'keep', 'ready')
    $receiptPath = Receipt-Path
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    Assert-True $receipt.complete 'Fresh setup did not complete.'
    Assert-True (@($script:calls | Where-Object { $_ -like '* secret set openai --oauth' }).Count -eq 1) 'OpenAI OAuth was not set once.'
    Assert-True (@($script:calls | Where-Object { $_ -like '* secret set github --sandbox cloud-test' }).Count -eq 1) 'GitHub scope is wrong.'
    Assert-True (@($script:calls | Where-Object { $_ -like '* create *--allow-network chatgpt.com:443*opencode' }).Count -eq 1) 'Initial network exceptions are missing.'
    Assert-True (@($script:calls | Where-Object { $_ -like '* create *--static-mcp context7 *' }).Count -eq 1) 'Context7 was not configured at creation.'
    Assert-True ($script:calls[$script:calls.Count - 1] -eq '--debug=false --cloud exec -it cloud-test bash') 'Setup did not end at sandbox Bash.'
    Assert-True (@($script:calls | Where-Object { $_ -match 'policy (allow|deny|init|rm|reset)|--force|sbx_local_opencode_deploy' }).Count -eq 0) 'Setup changed policy, forced credentials, or ran the installer.'
    $before = [IO.File]::ReadAllText($receiptPath)
    $stamp = (Get-Item -LiteralPath $receiptPath).LastWriteTimeUtc
    $script:calls.Clear()
    Run-Setup @('cloud-test', 'skip')
    Assert-True ($script:calls.Count -eq 0) 'An unchanged rerun called SBX.'
    Assert-True ([IO.File]::ReadAllText($receiptPath) -ceq $before) 'An unchanged rerun changed its receipt.'
    Assert-True ((Get-Item -LiteralPath $receiptPath).LastWriteTimeUtc -eq $stamp) 'An unchanged rerun wrote its receipt.'
    Run-Setup @('cloud-test', 'recheck', 'keep', 'keep', 'ready', 'ready', 'keep', 'ready')
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set|mcp load|policy allow' }).Count -eq 0) 'Recheck repeated a completed mutation.'
    Write-Host 'PASS: fresh setup, unchanged rerun, and explicit recheck'

    $script:calls.Clear()
    $script:quietNames = @('opencode/cloud-test')
    Run-Setup @('cloud-test', 'recheck', 'keep', 'keep', 'ready', 'ready', 'keep', 'ready')
    Assert-True (@($script:calls | Where-Object { $_ -like '* inspect cloud-test' }).Count -eq 1) 'Recorded name was not inspected directly.'
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set|mcp load' }).Count -eq 0) 'A list mismatch repeated a completed mutation.'
    Write-Host 'PASS: recorded sandbox resumes despite a name-list mismatch'

    Start-Case 'existing'
    $script:existingNames = @('cloud-test')
    Run-Setup @('cloud-test') '*name already exists*'
    Assert-True (-not (Test-Path -LiteralPath (Receipt-Path))) 'Setup claimed an existing sandbox.'
    Assert-True ($script:calls.Count -eq 1) 'Setup changed an existing sandbox.'
    Write-Host 'PASS: existing sandbox preservation'

    Start-Case 'secret-failure'
    $script:failCommand = '* secret set openai --oauth'
    Run-Setup @('cloud-test', 'oauth') '*exit 9*'
    Assert-True (-not (Test-Path -LiteralPath (Receipt-Path))) 'Failed secret setup saved a success receipt.'
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set github' }).Count -eq 0) 'Setup continued after a credential failure.'
    Write-Host 'PASS: credential failure stops setup'

    Start-Case 'create-interruption'
    $script:createThenFail = $true
    Run-Setup @('cloud-test', 'keep', 'keep', 'ready', 'ready', 'context7-custom', 'create') '*exit 7*'
    $receipt = Get-Content -LiteralPath (Receipt-Path) -Raw | ConvertFrom-Json
    Assert-True ($receipt.creationPending -and -not $receipt.created -and -not $receipt.complete) 'Failed creation was marked successful.'
    Assert-True ($receipt.mcp -eq 'context7-custom') 'The selected MCP name was not saved before creation.'
    Assert-True (@($script:calls | Where-Object { $_ -like '* create *--static-mcp context7-custom *' }).Count -eq 1) 'Creation ignored the selected MCP name.'
    $script:createThenFail = $false
    $script:calls.Clear()
    Run-Setup @('cloud-test', 'resume', 'load', 'ready')
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set' }).Count -eq 0) 'Resume repeated creation or secret setup.'
    Write-Host 'PASS: creation finished before receipt update'

    Start-Case 'mcp-failure'
    $script:failCommand = '* mcp load *'
    Run-Setup @('cloud-test', 'keep', 'keep', 'ready', 'ready', '', 'create', 'load') '*exit 9*'
    $receipt = Get-Content -LiteralPath (Receipt-Path) -Raw | ConvertFrom-Json
    Assert-True ($receipt.created -and -not $receipt.complete) 'MCP failure was marked complete.'
    $script:failCommand = ''
    $script:calls.Clear()
    Run-Setup @('cloud-test', 'keep', 'ready')
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set|mcp load' }).Count -eq 0) 'MCP recovery repeated completed work.'
    Write-Host 'PASS: MCP failure and safe retry'

    Start-Case 'missing-gateway'
    $script:mcpNoGateway = $true
    Run-Setup @('cloud-test', 'keep', 'keep', 'ready', 'ready', '', 'create') '*requires --static-mcp at creation*'
    $receipt = Get-Content -LiteralPath (Receipt-Path) -Raw | ConvertFrom-Json
    Assert-True (-not $receipt.complete) 'A missing gateway was marked complete.'
    Assert-True (@($script:calls | Where-Object { $_ -like '* mcp load *' }).Count -eq 0) 'Setup tried to load into a missing gateway.'
    $script:calls.Clear()
    Run-Setup @('cloud-test') '*requires --static-mcp at creation*'
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set|mcp load| rm ' }).Count -eq 0) 'Missing-gateway recovery changed an existing sandbox or secret.'
    Write-Host 'PASS: missing gateway stops with recovery instructions and preserves the sandbox'

    Start-Case 'mcp-status-error'
    $script:mcpStatusError = 'error: sbxcloud: not found; sandbox not found'
    Run-Setup @('cloud-test', 'keep', 'keep', 'ready', 'ready', '', 'create') '*MCP status failed (exit 1)*'
    Assert-True (@($script:calls | Where-Object { $_ -like '* mcp load *' }).Count -eq 0) 'An unrelated status error triggered attachment.'
    $receipt = Get-Content -LiteralPath (Receipt-Path) -Raw | ConvertFrom-Json
    Assert-True (-not $receipt.complete) 'An unrelated status error marked setup complete.'
    $script:mcpStatusError = ''
    Run-Setup @('cloud-test', 'keep', 'ready')
    Write-Host 'PASS: unrelated MCP status errors stop setup and permit retry'

    $script:calls.Clear()
    $script:existingNames = @()
    Run-Setup @('cloud-test', 'recheck') '*Cannot inspect the recorded sandbox*'
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set' }).Count -eq 0) 'Setup recreated an absent sandbox.'
    Write-Host 'PASS: expired sandbox preservation'

    Start-Case 'unknown-receipt'
    $receiptPath = Receipt-Path
    [IO.Directory]::CreateDirectory((Split-Path $receiptPath -Parent)) | Out-Null
    [IO.File]::WriteAllText($receiptPath, '{"owner":"someone-else"}')
    Run-Setup @('cloud-test') '*Unknown receipt*'
    Assert-True ($script:calls.Count -eq 0) 'Unknown receipt allowed CLI calls.'
    Assert-True ([IO.File]::ReadAllText($receiptPath) -ceq '{"owner":"someone-else"}') 'Unknown receipt was overwritten.'
    [IO.File]::WriteAllText($receiptPath, '{broken-json')
    Run-Setup @('cloud-test') '*Cannot read receipt*'
    Assert-True ([IO.File]::ReadAllText($receiptPath) -ceq '{broken-json') 'Damaged receipt was overwritten.'
    Run-Setup @('bad.name') '*Use 2-63*'
    Write-Host 'PASS: unknown receipt and invalid name'
} finally {
    $env:LOCALAPPDATA = $originalLocalAppData
    $resolvedTestDirectory = [IO.Path]::GetFullPath($testDirectory)
    $expectedParent = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
    if ((Split-Path $resolvedTestDirectory -Parent) -cne $expectedParent -or (Split-Path $resolvedTestDirectory -Leaf) -notlike '.cloud-setup-test-*') { throw 'Test cleanup path is outside the expected workspace directory.' }
    Remove-Item -LiteralPath $resolvedTestDirectory -Recurse -Force
}
}
