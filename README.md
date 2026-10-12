# solo-notifications

The notifications cell: notification rules and the notification log (what
was queued for which task snapshot, and whether a channel delivered it). It
keeps its own Neon database and reuses
[empire-platform](https://github.com/bookchaowalit/empire-platform) for
identity, authorization, executions and audit over HTTP with the caller's
token (same pattern as solo-decisions and solo-habits). Log entries are
operational records, so the cell publishes no graph events and runs no
publisher. Delivery runs in the cell too (`notifications-dispatch`, below).

| | |
|---|---|
| API | Railway project `solo-notifications`, service `notifications-api` (Serverless) |
| Dispatcher | service `notifications-dispatcher` (Railway cron, `*/30 * * * *`) |
| Data | Neon project `solo-notifications`, database `notifications` |
| Registry | solo-empire `repository-catalog/registries/online-systems.yaml` (`notifications`) |

## API

| Method | Path | Purpose |
|---|---|---|
| GET / POST | `/v1/notification-rules` | list (`active`, `rule_type`) / create |
| GET / PATCH | `/v1/notification-rules/{id}` | one rule / change it (`expected_version`) |
| GET | `/v1/notifications` | log (`notification_type`, `since`, `until`, `task_id`, `rule_id`, `undelivered`, `max_attempts`, `dedupe_key`, `order`, paging) |
| GET | `/v1/notifications/stats` | counts by type, severity or channel (`since`) |
| GET | `/v1/notifications/{id}` | one entry |
| POST | `/v1/notifications` | queue; a known `dedupe_key` returns the existing entry (`outcome: existing`) |
| POST | `/v1/notifications/{id}/delivery` | `delivered` (channel), `failed` (error), or `console` |

Permissions: `notifications.rule:read|write`, `notifications.notification:read|write`.

## Dispatcher

`notifications-dispatch [--dry-run]` evaluates the active rules (overdue,
due_soon, high_priority, stale, blocked, reminder) against the tasks cell,
queues each match once per rule, task snapshot and Bangkok day, then — outside
22:00-07:00 Asia/Bangkok — sends pending task entries as one Telegram digest
and each engagement review as its own message, records every result, and
acknowledges delivered explicit reminders on the task. A broken rule or entry
is logged and skipped. Variables (Railway only): `EMPIRE_TASKS_API`,
`EMPIRE_NOTIFICATIONS_API`, `NOTIFICATIONS_DISPATCH_TOKEN` (the 30-day
`reminder-worker` automation token; rotate with the other cell tokens),
`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`.

## MCP server (`notifications-mcp`)

`solo_notifications.mcp_server` is this cell's MCP server (stdio). Every tool calls the cell's HTTP API with the caller's own
token, so MCP has exactly the authorization the API has: it never touches the database, and no tool accepts
an actor, workspace, delegation or token argument (strict models reject unknown arguments before any HTTP
call). Errors reach the client as a fixed message from the HTTP status only (for example `403: forbidden`), never upstream text; tokens with whitespace or control characters are refused.

- Tools: `notifications.rule.{list,get}`, `notifications.notification.{list,get,stats}`.
- Write tools: `notifications.notification.create` (console-only note of kind note/agent_note/status_change, which the dispatcher never sends), `notifications.rule.create` (always inactive) and `notifications.rule.update` (not channels or the active flag), so MCP can never cause an outside message. Set `EMPIRE_MCP_READONLY=1` to register only the read tools.
- URL: `EMPIRE_NOTIFICATIONS_API` (env, else the owner-only `~/.config/empire-platform/client.env`); https only (http only on loopback), no credentials, query or fragment.
- Token, first match wins: `EMPIRE_TOKEN`, `EMPIRE_TOKEN_FILE` (mode 600), then the automation token named by
  `EMPIRE_MCP_AUTOMATION` (default `owner-cli`, lower-case letters, digits and hyphens) from `EMPIRE_AUTOMATION_TOKEN_<NAME>` or
  `~/.config/empire-platform/tokens/<name>.jwt`.
- Run: `uv pip install --python .venv/bin/python -e ".[mcp]"`, then `.venv/bin/notifications-mcp` (see `.mcp.json`).
- Tests: `.venv/bin/pytest tests/test_mcp.py` (fake HTTP transport; no database, no network).

## Develop and operate

```bash
uv venv .venv && uv pip install --python .venv/bin/python -e ".[dev]"
.venv/bin/pytest -q          # add ../empire-platform[dev] for the end-to-end test
NEON_API_KEY=... .venv/bin/notifications-db provision
npm install && railway config apply && railway up --ci --service notifications-api
railway up --ci --service notifications-dispatcher
railway run --service notifications-dispatcher -- .venv/bin/notifications-dispatch --dry-run
```

Railway variables (never in the repository): `NOTIFICATIONS_DB_MODE=hosted`,
`NOTIFICATIONS_DB_URL_API`, `NOTIFICATIONS_JWT_PUBLIC_KEY_PEM`,
`NOTIFICATIONS_JWT_ISSUER`, `EMPIRE_PLATFORM_URL`.
