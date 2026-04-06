# GitHub Issue Record: INVALID_REQUEST on Single-Agent Task Mode

- Date: 2026-04-06
- Source: In-app error report from desktop app (Task chat mode -> Single Agent)
- Scope: Task conversation in `单机智能体` mode

## Title

`INVALID_REQUEST: invalid chat.send params: at root: unexpected property 'metadata'`

## Reproduction Steps

1. Open XWorkmate app.
2. Click **新对话**.
3. In task mode selector, choose **任务对话模式 -> 单机智能体**.
4. Send any message.
5. Observe error in conversation pane:
   - `INVALID_REQUEST: invalid chat.send params: at root: unexpected property 'metadata'`

## Actual Result

The conversation fails immediately and returns request validation error because `chat.send` request payload contains an unexpected root-level `metadata` field.

## Expected Result

Single-agent task chat should send a provider-compatible payload and complete message dispatch without schema validation errors.

## Impact

- Users cannot reliably start new single-agent task conversations.
- Reproducible in normal workflow, blocks core single-agent usage path.

## Notes for Follow-up

- Inspect request assembly path for single-agent `chat.send` payload.
- Confirm whether metadata must be nested, filtered, or omitted for the current provider endpoint.
- Add regression tests for provider schema compatibility in single-agent mode.
