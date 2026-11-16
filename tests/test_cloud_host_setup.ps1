# Test the host setup script with fake CLI calls. Do not contact Docker.
& {
$ErrorActionPreference = 'Stop'
$setupPath = Join-Path $PSScriptRoot '..\sbx_cloud_host_setup_win.ps1'
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($setupPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$setupBlock = $ast.GetScriptBlock()
$originalLocalAppData = $env:LOCALAPPDATA
$originalTerm = $env:TERM
$originalColumns = $env:COLUMNS
# Use the line-input fallback for repeatable tests, including interactive runs.
$env:TERM = 'dumb'
$testDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) ('.cloud-setup-test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($testDirectory) | Out-Null
$script:calls = [Collections.Generic.List[string]]::new()
$script:answers = [Collections.Generic.Queue[string]]::new()
$script:existingNames = @()
$script:quietNames = $null
$script:failCommand = ''
$script:createThenFail = $false
$script:secretInputLengths = [Collections.Generic.List[int]]::new()
$script:maskedPromptCount = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}
function Read-Host([string]$Prompt, [switch]$AsSecureString) {
    if (-not $script:answers.Count) { throw "No test answer for: $Prompt" }
    $answer = $script:answers.Dequeue()
    if ($AsSecureString) {
        $script:maskedPromptCount++
        $secureAnswer = [Security.SecureString]::new()
        foreach ($character in $answer.ToCharArray()) { $secureAnswer.AppendChar($character) }
        return $secureAnswer
    }
    return $answer
}
function Get-Command {
    # The guide requires an installed CLI. Supply that prerequisite for tests.
    return [pscustomobject]@{ Name = 'sbx'; CommandType = 'Application' }
}
function sbx {
    $command = @($args) -join ' '
    $script:calls.Add($command)
    $inputValues = @($input)
    if ($command -match ' secret set (github|openai) --sandbox | secret set-custom ') {
        Assert-True ($inputValues.Count -eq 1) 'A key was not passed through standard input.'
        $script:secretInputLengths.Add($inputValues[0].Length)
    }
    $global:LASTEXITCODE = 0
    if ($command -like '* create *' -and $script:createThenFail) {
        $script:existingNames = @('cloud-test')
        $global:LASTEXITCODE = 7
        return
    }
    if ($script:failCommand -and $command -like $script:failCommand) { $global:LASTEXITCODE = 9; return }
    if ($command -like '* ls --quiet') {
        if ($null -ne $script:quietNames) { $script:quietNames } else { $script:existingNames }
        return
    }
    if ($command -like '* inspect cloud-test' -and $script:existingNames -notcontains 'cloud-test') { Write-Error "error: sandbox 'cloud-test' not found" -ErrorAction Continue; $global:LASTEXITCODE = 1; return }
    if ($command -like '* policy ls*') { 'Account deny remains: intentional.example:443'; return }
    if ($command -like '* create *') { $script:existingNames = @('cloud-test') }
}
function Run-Setup([string[]]$Replies, [string]$ExpectedError = '') {
    $script:answers.Clear()
    foreach ($reply in $Replies) { $script:answers.Enqueue($reply) }
    $caught = ''
    $script:lastOutput = [Collections.Generic.List[string]]::new()
    try { & $setupBlock *>&1 | ForEach-Object { $script:lastOutput.Add($_.ToString()) } } catch { $caught = $_.Exception.Message }
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
    $script:secretInputLengths.Clear()
    $script:maskedPromptCount = 0
}
function Receipt-Path { return (Join-Path $env:LOCALAPPDATA 'sbx-deploy\cloud\cloud-test.json') }
try {
    Start-Case 'fresh'
    Run-Setup @('cloud-test', '2', '2', 'test-only-github-secret', '1', '', '', 'y', '')
    $receiptPath = Receipt-Path
    $receipt = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    Assert-True $receipt.complete 'Fresh setup did not complete.'
    Assert-True ($script:maskedPromptCount -eq 1 -and $script:secretInputLengths[0] -eq 'test-only-github-secret'.Length) 'GitHub entry was not masked and sent through stdin.'
    Assert-True (($script:calls -join "`n") -notmatch 'test-only-github-secret') 'The GitHub value leaked into command arguments.'
    Assert-True (($script:lastOutput -join "`n") -notmatch 'test-only-github-secret') 'The GitHub value leaked into output.'
    Assert-True ([IO.File]::ReadAllText($receiptPath) -notmatch 'test-only-github-secret') 'The GitHub value leaked into the receipt.'
    Assert-True (@($script:calls | Where-Object { $_ -like '* secret set openai --oauth' }).Count -eq 1) 'OpenAI OAuth was not set once.'
    Assert-True (@($script:calls | Where-Object { $_ -like '* secret set github --sandbox cloud-test' }).Count -eq 1) 'GitHub scope is wrong.'
    Assert-True (@($script:calls | Where-Object { $_ -like '* create *--allow-network chatgpt.com:443*opencode' }).Count -eq 1) 'Initial network exceptions are missing.'
    Assert-True (@($script:calls | Where-Object { $_ -match '--static-mcp| mcp (ls|load) ' }).Count -eq 0) 'Setup used the failing Docker gateway path.'
    Assert-True (@($script:calls | Where-Object { $_ -like '* create *--allow-network mcp.context7.com:443*' }).Count -eq 1) 'Context7 network access is missing.'
    Assert-True ($script:calls[$script:calls.Count - 1] -eq '--debug=false --cloud exec -it cloud-test bash') 'Setup did not end at sandbox Bash.'
    Assert-True (@($script:calls | Where-Object { $_ -match 'policy (allow|deny|init|rm|reset)|--force|sbx_local_opencode_deploy' }).Count -eq 0) 'Setup changed policy, forced credentials, or ran the installer.'
    $before = [IO.File]::ReadAllText($receiptPath)
    $stamp = (Get-Item -LiteralPath $receiptPath).LastWriteTimeUtc
    $script:calls.Clear()
    Run-Setup @('cloud-test', '')
    Assert-True ($script:calls.Count -eq 0) 'An unchanged rerun called SBX.'
    Assert-True ([IO.File]::ReadAllText($receiptPath) -ceq $before) 'An unchanged rerun changed its receipt.'
    Assert-True ((Get-Item -LiteralPath $receiptPath).LastWriteTimeUtc -eq $stamp) 'An unchanged rerun wrote its receipt.'
    Run-Setup @('cloud-test', '2', '1', '1', '1', '', '', '')
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set|mcp load|policy allow' }).Count -eq 0) 'Recheck repeated a completed mutation.'
    Write-Host 'PASS: fresh setup, unchanged rerun, and explicit recheck'

    $script:calls.Clear()
    $script:quietNames = @('opencode/cloud-test')
    Run-Setup @('cloud-test', '2', '1', '1', '1', '', '', '')
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
    Run-Setup @('cloud-test', '2') '*exit 9*'
    Assert-True (-not (Test-Path -LiteralPath (Receipt-Path))) 'Failed secret setup saved a success receipt.'
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set github' }).Count -eq 0) 'Setup continued after a credential failure.'
    Write-Host 'PASS: credential failure stops setup'

    Start-Case 'masked-openai-key'
    Run-Setup @('cloud-test', '3', 'test-only-openai-key', '1', '1', '', '', 'y', '')
    Assert-True ($script:maskedPromptCount -eq 1 -and $script:secretInputLengths[0] -eq 'test-only-openai-key'.Length) 'OpenAI key entry was not masked and sent through stdin.'
    Assert-True (($script:calls -join "`n") -notmatch 'test-only-openai-key') 'The OpenAI key leaked into arguments.'
    Assert-True (($script:lastOutput -join "`n") -notmatch 'test-only-openai-key') 'The OpenAI key leaked into output.'
    Write-Host 'PASS: masked OpenAI API key entry'

    Start-Case 'empty-secret'
    Run-Setup @('cloud-test', '1', '2', '') '*Secret input is empty*'
    Assert-True ($script:secretInputLengths.Count -eq 0) 'Empty input was sent to SBX.'
    Assert-True (-not (Test-Path -LiteralPath (Receipt-Path))) 'Empty input saved a receipt.'
    Write-Host 'PASS: empty secret is rejected before saving'

    Start-Case 'masked-save-failure'
    $script:failCommand = '* secret set github *'
    Run-Setup @('cloud-test', '1', '2', 'test-only-failed-secret') '*exit 9*'
    Assert-True (($script:lastOutput -join "`n") -notmatch 'test-only-failed-secret|Secret saved\.') 'Failed save leaked the value or reported success.'
    Assert-True (-not (Test-Path -LiteralPath (Receipt-Path))) 'Failed key save wrote a receipt.'
    Write-Host 'PASS: failed masked save stops without reporting success'

    Start-Case 'create-interruption'
    $script:createThenFail = $true
    Run-Setup @('cloud-test', '1', '1', '1', '', '', 'y') '*exit 7*'
    $receipt = Get-Content -LiteralPath (Receipt-Path) -Raw | ConvertFrom-Json
    Assert-True ($receipt.creationPending -and -not $receipt.created -and -not $receipt.complete) 'Failed creation was marked successful.'
    Assert-True ($receipt.version -eq 2) 'The direct-connection receipt version was not saved.'
    $script:createThenFail = $false
    $script:calls.Clear()
    Run-Setup @('cloud-test', 'y', '')
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set' }).Count -eq 0) 'Resume repeated creation or secret setup.'
    Write-Host 'PASS: creation finished before receipt update'

    Start-Case 'placeholder-failure'
    $script:failCommand = '* exec *CONTEXT7_API_KEY*'
    Run-Setup @('cloud-test', '1', '1', '1', '', '', 'y') '*exit 9*'
    $receipt = Get-Content -LiteralPath (Receipt-Path) -Raw | ConvertFrom-Json
    Assert-True ($receipt.created -and -not $receipt.complete) 'MCP failure was marked complete.'
    $script:failCommand = ''
    $script:calls.Clear()
    Run-Setup @('cloud-test', '')
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set|mcp load' }).Count -eq 0) 'MCP recovery repeated completed work.'
    Write-Host 'PASS: placeholder check failure and safe retry'

    Start-Case 'global-context7'
    Run-Setup @('cloud-test', '1', '1', '2', 'test-only-context7-key', '', '', 'y', '')
    $customCommand = @($script:calls | Where-Object { $_ -match ' secret set-custom ' })
    Assert-True ($customCommand.Count -eq 1 -and $customCommand[0] -match '--host mcp.context7.com .*--header Authorization --format Bearer %s --value-stdin') 'The cloud proxy header configuration is wrong.'
    Assert-True ($customCommand[0] -notmatch '--sandbox|test-only-context7-key') 'The Context7 key was scoped to one sandbox or leaked into arguments.'
    Assert-True (($script:lastOutput -join "`n") -notmatch 'test-only-context7-key') 'The Context7 key leaked into output.'
    Write-Host 'PASS: global Context7 key uses masked stdin and cloud Bearer injection'

    $receiptPath = Receipt-Path
    $legacy = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    $legacy.version = 1
    [IO.File]::WriteAllText($receiptPath, ($legacy | ConvertTo-Json -Depth 4))
    $script:calls.Clear()
    Run-Setup @('cloud-test', '1', '1', '1', '', '', '')
    $migrated = Get-Content -LiteralPath $receiptPath -Raw | ConvertFrom-Json
    Assert-True ($migrated.version -eq 2 -and $migrated.complete) 'Legacy preparation was not reviewed and migrated.'
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set' }).Count -eq 0) 'Legacy migration recreated a sandbox or replaced secrets.'
    Write-Host 'PASS: legacy receipts require review before migration'

    $script:calls.Clear()
    $script:existingNames = @()
    $receiptBefore = [IO.File]::ReadAllText((Receipt-Path))
    Run-Setup @('cloud-test', '2', 'n') '*Setup cancelled*'
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set' }).Count -eq 0) 'Setup recreated a sandbox without confirmation.'
    Assert-True ([IO.File]::ReadAllText((Receipt-Path)) -ceq $receiptBefore) 'Cancelled recreation changed the receipt.'
    Write-Host 'PASS: declined recreation preserves the receipt and secrets'

    $script:calls.Clear()
    $script:failCommand = '* inspect cloud-test'
    Run-Setup @('cloud-test', '2') '*Cannot inspect the recorded sandbox*exit 9*'
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set' }).Count -eq 0) 'An unrelated inspection error triggered recreation.'
    Assert-True ([IO.File]::ReadAllText((Receipt-Path)) -ceq $receiptBefore) 'An inspection failure changed the receipt.'
    $script:failCommand = ''
    Write-Host 'PASS: unrelated inspection errors cannot trigger recreation'

    $script:calls.Clear()
    Run-Setup @('cloud-test', '2', 'y', '1', '1', '1', '', '', 'y', '')
    Assert-True (@($script:calls | Where-Object { $_ -match ' create ' }).Count -eq 1) 'Approved recreation did not create exactly one sandbox.'
    Assert-True (@($script:calls | Where-Object { $_ -match 'secret set| rm ' }).Count -eq 0) 'Recreation replaced secrets or removed a sandbox.'
    $recreated = Get-Content -LiteralPath (Receipt-Path) -Raw | ConvertFrom-Json
    Assert-True ($recreated.created -and $recreated.complete) 'Recreation did not save a complete receipt.'
    $script:calls.Clear()
    Run-Setup @('cloud-test', '')
    Assert-True ($script:calls.Count -eq 0) 'Unchanged rerun after recreation called SBX.'
    Write-Host 'PASS: approved recreation reuses secrets and preserves unchanged reruns'

    $recreated.version = 1
    [IO.File]::WriteAllText((Receipt-Path), ($recreated | ConvertTo-Json -Depth 4))
    $script:existingNames = @()
    $script:calls.Clear()
    Run-Setup @('cloud-test', 'y', '1', '1', '1', '', '', 'y', '')
    $recoveredLegacy = Get-Content -LiteralPath (Receipt-Path) -Raw | ConvertFrom-Json
    Assert-True ($recoveredLegacy.version -eq 2 -and $recoveredLegacy.complete) 'A missing sandbox with an old receipt could not be recreated.'
    Assert-True (@($script:calls | Where-Object { $_ -match 'secret set' }).Count -eq 0) 'Legacy recreation replaced existing secrets.'
    Write-Host 'PASS: missing sandbox recovery also handles old gateway-mode receipts'

    Start-Case 'numbered-choice-retry'
    Run-Setup @('cloud-test', 'keep', '4', '1', '1', '1', '', '', 'y', '')
    Assert-True (($script:lastOutput -join "`n") -match 'Choose a number from 1 to 3') 'Invalid menu input was not retried.'
    Assert-True (@($script:calls | Where-Object { $_ -match 'secret set' }).Count -eq 0) 'A keep selection changed credentials.'
    Write-Host 'PASS: numbered choices reject words and invalid numbers'

    Start-Case 'escape-cancel'
    $env:COLUMNS = '32'
    Run-Setup @('cloud-test', ([string][char]27)) '*Setup cancelled*'
    Assert-True (@($script:calls | Where-Object { $_ -match ' create |secret set' }).Count -eq 0) 'Escape did not stop before mutations.'
    Assert-True (-not (Test-Path -LiteralPath (Receipt-Path))) 'Escape created a receipt.'
    $narrowOutput = $script:lastOutput -join "`n"
    Assert-True ($narrowOutput -match 'S B X   D E P L O Y' -and $narrowOutput -notmatch '\.---|\+---') 'The narrow layout used the full banner or borders.'
    Assert-True ($narrowOutput -notmatch [string][char]27) 'Plain terminal output contains ANSI escape codes.'
    Write-Host 'PASS: Escape cancellation and narrow plain layout'
    $env:COLUMNS = $originalColumns

    foreach ($cancelKey in @('n', '', '0')) {
        Start-Case ('creation-cancel-' + [guid]::NewGuid().ToString('N'))
        Run-Setup @('cloud-test', '1', '1', '1', '', '', $cancelKey) '*Setup cancelled*'
        Assert-True (@($script:calls | Where-Object { $_ -match ' create ' }).Count -eq 0) 'Creation did not require an explicit y.'
        $receipt = Get-Content -LiteralPath (Receipt-Path) -Raw | ConvertFrom-Json
        Assert-True (-not $receipt.creationPending -and -not $receipt.created) 'Cancelled creation changed creation progress.'
    }
    Write-Host 'PASS: n, Enter, and 0 cancel creation without creating a sandbox'

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
    $env:TERM = $originalTerm
    $env:COLUMNS = $originalColumns
    $resolvedTestDirectory = [IO.Path]::GetFullPath($testDirectory)
    $expectedParent = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
    if ((Split-Path $resolvedTestDirectory -Parent) -cne $expectedParent -or (Split-Path $resolvedTestDirectory -Leaf) -notlike '.cloud-setup-test-*') { throw 'Test cleanup path is outside the expected workspace directory.' }
    Remove-Item -LiteralPath $resolvedTestDirectory -Recurse -Force
}
}
