# API Reference

Complete list of commands available through the Pi Mobile Agent backend.

## WebSocket Protocol

All commands are sent as JSON objects through WebSocket and receive JSON responses.

### Command Format
```json
{
  "id": "unique-request-id",
  "command": "command_name",
  "param1": "value1",
  "param2": "value2"
}
```

### Response Format
```json
{
  "id": "unique-request-id",
  "type": "response",
  "command": "command_name",
  "success": true,
  "data": { /* command-specific data */ },
  "error": null
}
```

## Commands

### prompt

Send a prompt to the Pi agent to execute a task.

**Request:**
```json
{
  "id": "req-1",
  "command": "prompt",
  "message": "Create a Flutter counter app"
}
```

**Response:**
```json
{
  "id": "req-1",
  "type": "response",
  "command": "prompt",
  "success": true,
  "data": {
    "disposition": "started"
  }
}
```

**Dispositions:**
- `"started"`: Run began, watch for `agent_settled` event
- `"handled"`: Extension handled it, no run started
- `"queued"`: Added to run queue

**Examples:**
- "Create a Python Flask API"
- "Fix this bug: [code]"
- "Write unit tests for this module"
- "List all files in the project"
- "Explain how this code works"

---

### abort

Stop the currently running task.

**Request:**
```json
{
  "id": "req-2",
  "command": "abort"
}
```

**Response:**
```json
{
  "id": "req-2",
  "type": "response",
  "command": "abort",
  "success": true
}
```

---

### get_state

Get the current state of the Pi agent.

**Request:**
```json
{
  "id": "req-3",
  "command": "get_state"
}
```

**Response:**
```json
{
  "id": "req-3",
  "type": "response",
  "command": "get_state",
  "success": true,
  "data": {
    "model": "claude-3-5-sonnet-20241022",
    "messageCount": 5,
    "isProcessing": false,
    "systemPrompt": "You are a helpful coding assistant..."
  }
}
```

---

### get_messages

Get message history from the current session.

**Request:**
```json
{
  "id": "req-4",
  "command": "get_messages"
}
```

**Response:**
```json
{
  "id": "req-4",
  "type": "response",
  "command": "get_messages",
  "success": true,
  "data": {
    "messages": [
      {
        "id": "msg-1",
        "role": "user",
        "content": "Create a counter app",
        "timestamp": "2024-01-20T10:30:00Z"
      },
      {
        "id": "msg-2",
        "role": "assistant",
        "content": "I'll create a Flutter counter app...",
        "timestamp": "2024-01-20T10:30:05Z"
      }
    ],
    "total": 2
  }
}
```

---

### set_model

Change the AI model being used.

**Request:**
```json
{
  "id": "req-5",
  "command": "set_model",
  "model": "claude-3-opus-20250219"
}
```

**Response:**
```json
{
  "id": "req-5",
  "type": "response",
  "command": "set_model",
  "success": true,
  "data": {
    "model": "claude-3-opus-20250219"
  }
}
```

**Available Models (depends on your provider):**

Anthropic:
- `claude-3-5-sonnet-20241022` (balanced, fastest)
- `claude-3-opus-20250219` (most powerful)
- `claude-3-haiku-20240307` (fastest, lightweight)

OpenAI:
- `gpt-4o` (latest)
- `gpt-4-turbo` (reliable)
- `gpt-4` (legacy)

---

### get_available_models

Get list of available AI models.

**Request:**
```json
{
  "id": "req-6",
  "command": "get_available_models"
}
```

**Response:**
```json
{
  "id": "req-6",
  "type": "response",
  "command": "get_available_models",
  "success": true,
  "data": {
    "models": [
      {
        "id": "claude-3-5-sonnet-20241022",
        "name": "Claude 3.5 Sonnet",
        "provider": "anthropic",
        "available": true
      },
      {
        "id": "claude-3-opus-20250219",
        "name": "Claude 3 Opus",
        "provider": "anthropic",
        "available": true
      }
    ]
  }
}
```

---

### get_session_stats

Get token totals, cost and current context-window usage for the backend's Pi
session. The app calls it after a run settles (`agent_settled`) so the progress
line can show real context usage.

**Request:**
```json
{
  "id": "req-7",
  "command": "get_session_stats"
}
```

**Response:**
```json
{
  "id": "req-7",
  "type": "response",
  "command": "get_session_stats",
  "success": true,
  "data": {
    "sessionFile": "/path/to/session.jsonl",
    "sessionId": "abc123",
    "userMessages": 5,
    "assistantMessages": 5,
    "toolCalls": 12,
    "tokens": {
      "input": 50000,
      "output": 10000,
      "cacheRead": 40000,
      "cacheWrite": 5000,
      "total": 105000
    },
    "cost": 0.45,
    "contextUsage": {
      "tokens": 60000,
      "contextWindow": 200000,
      "percent": 30
    }
  }
}
```

`contextUsage` is omitted when no model is available, and its `tokens` /
`percent` are `null` immediately after compaction until the next assistant
response.

---

### resume_session

Load a saved session into the live Pi runtime - the app's "Resume a session"
sheet. Session paths come from `list_sessions` (or `GET /api/sessions`).

Pi restores a session **in the directory that conversation was recorded in**, so
resuming also moves the working directory. The backend follows it: the response
carries the new `cwd`, and every later `get_state`, `list_dir` and `/health`
reports it too. Afterwards call `get_messages` for the restored conversation.

**Request:**
```json
{
  "id": "req-8",
  "command": "resume_session",
  "sessionPath": "/home/adam/.pi/agent/sessions/--home-adam--/2026-01-02.jsonl"
}
```

**Response:**
```json
{
  "id": "req-8",
  "type": "response",
  "command": "resume_session",
  "success": true,
  "data": {
    "cancelled": false,
    "cwd": "/home/adam/projects/other",
    "cwdDisplay": "~/projects/other"
  }
}
```

`cancelled: true` means an extension vetoed the switch (`session_before_switch`)
and nothing moved. If the directory the session was recorded in no longer exists,
Pi refuses the resume and the error names both the missing directory and the one
still in use.

---

### new_session

Start a fresh Pi conversation in the directory Pi is already working in - the
app's **`+` button in the top-left of the app bar** (like `/new` in the Pi TUI).
The working directory, model and settings are untouched; only the conversation
restarts. The session being left behind stays on disk and is still listed by
`list_sessions`.

**Request:**
```json
{
  "id": "req-9",
  "command": "new_session"
}
```

**Response:**
```json
{
  "id": "req-9",
  "type": "response",
  "command": "new_session",
  "success": true,
  "data": {
    "cancelled": false,
    "cwd": "/home/adam/projects/app",
    "cwdDisplay": "~/projects/app"
  }
}
```

`cancelled: true` means an extension vetoed the switch (`session_before_switch`)
and the current conversation is still live. The app clears its chat only when the
command succeeds, and the button is disabled while a run is in flight.

---

### client_metrics

Sent by the app on load, after the page settles, and on every viewport change. The
backend only logs it — it is the two sides of a phone layout problem in one line:
what Flutter's view thinks it is (`flutter`) and what the browser laid the page
out as (`browser`), including the size of Flutter's own host element and the safe
areas the app is laying out under.

```json
{
  "id": "req-10",
  "command": "client_metrics",
  "metrics": {
    "n": 1,
    "flutter": {"physical": "393x754", "logical": "393.0x754.0", "dpr": 1},
    "browser": {
      "inner": "393x720", "client": "393x720", "visual": "393x720 offsetTop 0 scale 1",
      "screen": "393x852", "dpr": 1,
      "viewportMeta": "width=device-width, initial-scale=1.0, maximum-scale=5.0, viewport-fit=cover",
      "hostRect": "top 0 bottom 720 width 393 height 720",
      "cssInsets": "48/0/34/0"
    },
    "appliedInsets": {"top": 48, "right": 0, "bottom": 34, "left": 0}
  }
}
```

Read them off the service log:

```bash
journalctl --user -u pi-mobile-agent | grep client_metrics
```

When `flutter` and `browser` disagree, the app is drawing and hit-testing at one
size while the page is laid out at another: a gap at the bottom of the screen,
and taps that land somewhere other than the widget they were aimed at. A reply is
sent only so the app can retire the request; nothing acts on it.

---

## Streaming events

The backend forwards every Pi record to all connected clients as
`{ "type": "pi_event", "event": { ... } }`. Two of them carry the numbers the
progress line shows:

```json
{"type":"message_update","usage":{"input":10,"output":224,"cacheRead":0,"cacheWrite":5870,"totalTokens":6104,"cost":{"total":0.0085},"reasoning":168},"assistantMessageEvent":{"type":"thinking_delta","contentIndex":0,"delta":"..."}}
```

`usage` is cumulative **for the assistant response currently streaming** — the
next tool round starts a fresh count — and some providers report zeros until the
response completes. `message_end` repeats the final usage on
`message.usage`, which is what the app sums up for the whole run and shows on
the finished bubble.

`tool_execution_update` carries `partialResult`, the tool's latest partial
result; the app counts its growth as "chars" so a long file read visibly
progresses. A tool may replace it rather than extend it, so only the increase is
counted.

---

## HTTP API Endpoints

Additionally, the backend exposes HTTP endpoints for simpler use cases:

### GET /health

Health check endpoint.

```bash
curl http://localhost:3000/health
```

Response:
```json
{
  "status": "ok",
  "pi_connected": true
}
```

---

### GET /api/models

Get available models.

```bash
curl http://localhost:3000/api/models
```

Response:
```json
{
  "models": [
    {
      "id": "claude-3-5-sonnet-20241022",
      "name": "Claude 3.5 Sonnet",
      "provider": "anthropic",
      "available": true
    }
  ]
}
```

---

### GET /api/state

Get current Pi state.

```bash
curl http://localhost:3000/api/state
```

Response:
```json
{
  "model": "claude-3-5-sonnet-20241022",
  "messageCount": 5,
  "isProcessing": false
}
```

---

### POST /api/prompt

Send a prompt (one-shot, HTTP endpoint).

```bash
curl -X POST http://localhost:3000/api/prompt \
  -H "Content-Type: application/json" \
  -d '{"message": "Hello Pi"}'
```

Response:
```json
{
  "success": true,
  "data": {
    "disposition": "started"
  }
}
```

> Note: For real-time event streaming, use WebSocket instead.

---

## Event Stream

When connected via WebSocket, you receive a continuous stream of events describing what Pi is doing:

### message_update

Text being streamed from the model.

```json
{
  "type": "pi_event",
  "event": {
    "type": "message_update",
    "assistantMessageEvent": {
      "type": "text_delta",
      "delta": "Here's the solution..."
    }
  }
}
```

### tool_call

Pi calling a tool (bash, file operations, etc.).

```json
{
  "type": "pi_event",
  "event": {
    "type": "tool_call",
    "toolName": "bash",
    "input": {
      "command": "ls -la"
    }
  }
}
```

### tool_result

Result from a tool execution.

```json
{
  "type": "pi_event",
  "event": {
    "type": "tool_result",
    "toolName": "bash",
    "output": "total 24\ndrwxr-xr-x..."
  }
}
```

### agent_settled

Agent completed all work and won't continue automatically.

```json
{
  "type": "pi_event",
  "event": {
    "type": "agent_settled"
  }
}
```

---

## Error Handling

Errors are reported in two ways:

### Command Error
```json
{
  "id": "req-1",
  "type": "response",
  "command": "set_model",
  "success": false,
  "error": "Model not found: invalid/model"
}
```

### Connection Error
```json
{
  "type": "error",
  "error": "Pi client not initialized"
}
```

### Common Errors
- `"Not connected to Pi backend"` - App not connected to backend
- `"Pi client not initialized"` - Backend not ready
- `"Command timeout"` - Task took too long (30s)
- `"Model not found"` - Invalid model ID
- `"Failed to parse command"` - Malformed JSON

---

## Rate Limiting

No built-in rate limiting, but consider:
- One prompt at a time (queue subsequent ones)
- Reasonable prompt size (< 100KB)
- Don't spam commands

---

## Timeouts

- **Command timeout**: 30 seconds (can be increased)
- **Reconnect delay**: 5 seconds between attempts
- **Connection timeout**: 30 seconds

---

## Request ID Correlation

Always use unique request IDs to correlate responses:

```javascript
const requestId = `req-${Date.now()}-${Math.random()}`;
```

Then match the response by ID.

---

## Examples

### Complete Workflow

1. **Connect WebSocket**
   - Flutter app connects to `ws://server:3000`

2. **Get Available Models**
   ```json
   {"id":"1","command":"get_available_models"}
   ```

3. **Send Prompt**
   ```json
   {"id":"2","command":"prompt","message":"Create a counter app"}
   ```

4. **Receive Events**
   - Multiple `message_update` events with streamed text
   - Possibly `tool_call` and `tool_result` events
   - Finally `agent_settled` event

5. **Abort if Needed**
   ```json
   {"id":"3","command":"abort"}
   ```

6. **Check State**
   ```json
   {"id":"4","command":"get_state"}
   ```

---

## Adding Custom Commands

To add a new command to the backend:

1. Add method to `PiRpcClient` in `backend/src/pi-rpc-client.ts`
2. Add handler in `backend/src/index.ts`
3. Call it from Flutter: `piService.sendCommand()`

Example:

**Backend:**
```typescript
async setThinkingLevel(level: string): Promise<RpcResponse> {
  return this.sendCommand({
    type: "set_thinking_level",
    thinkingLevel: level,
  });
}
```

**Flutter:**
```dart
Future<void> changeThinkingLevel(String level) async {
  final response = await piService.sendCommand(
    'set_thinking_level',
    params: {'thinkingLevel': level},
  );
}
```

---

## Debugging

### Log All Commands
Add to `PiService` in Flutter:
```dart
print('Sending: ${jsonEncode(message)}');
```

### Log Backend Activity
Backend already logs all commands and events to console.

### Network Inspector
Use browser DevTools or Charles Proxy to see WebSocket frames.

---

## Performance Tips

- Keep event history manageable (~100 items)
- Batch rapid commands when possible
- Dispose subscriptions properly
- Close WebSocket connection on app exit
- Don't hold large message lists in memory

---

## Security Considerations

- Don't expose backend to internet without authentication
- Validate all input on backend before passing to Pi
- Use WSS (secure WebSocket) for production
- Implement rate limiting if publicly exposed
- Store credentials securely (already done by Pi)

---

**Last Updated:** January 2025  
**Version:** 1.0.0  
**Pi Agent Version:** 1.4.0+
