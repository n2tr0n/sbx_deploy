# Cloud sandbox setup

## 1. Find the sandbox

In **Windows PowerShell**:

```powershell
sbx --cloud ls
```

Replace `<sandbox-id>` below with the name or ID from this list.

## 2. Check network rules

In **Windows PowerShell**, inspect account and sandbox rules:

```powershell
sbx --cloud policy ls
```

```powershell
sbx --cloud policy ls <sandbox-id>
```

## 3. Allow required downloads

Skip this step if all four hosts are already allowed. Keep intentional denies.
For missing Codex or VS Code download access, add a sandbox-scoped rule in
**Windows PowerShell**:

```powershell
sbx --cloud policy allow network "chatgpt.com:443,releases.openai.com:443,update.code.visualstudio.com:443,vscode.download.prss.microsoft.com:443" --sandbox <sandbox-id>
```

## 4. Deploy and check

Paste the complete `sbx_local_opencode_deploy.sh` into **cloud sandbox Bash**.
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
