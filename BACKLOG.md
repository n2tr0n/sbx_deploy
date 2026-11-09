# Reported issues

Check each report against current code before making changes. AI reports below
are unverified. Record reproduction evidence. Update or close each entry after investigation.

- [Unreproduced] Codex "broken pipe" during selection or copying: investigate if it recurs. Record reproduction steps, versions, and relevant output.

- [Alpha review; code confirmed] Preserve explicit local authentication choices on rerun. With host OAuth enabled, the OpenCode import selects `sbx-openai` again. The Codex defaults select `sbx-chatgpt` again after local login selects `openai`. Add a persistent choice or an explicit reset option. Check both harnesses in a sandbox after repair.
- [Alpha review; fixture confirmed for OpenCode] Preserve deliberate model and MCP overrides. The defaults replace existing model, agent model, and gateway values without an ownership baseline. Codex also replaces these values. Record deployment ownership or stop with recovery instructions when ownership is uncertain. Check upgrade preservation and unchanged reruns after repair.
