import express from "express";
import cors from "cors";
import { WebSocketServer, WebSocket } from "ws";
import { createServer } from "http";
import { spawn } from "child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "fs";
import os from "os";
import path from "path";
import PiRpcClient from "./pi-rpc-client.js";
import { listPiSessions } from "./session-store.js";
import { listDirectory, resolveExistingDir, shrinkHome } from "./fs-browser.js";

const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });

app.use(cors());
app.use(express.json());

// Global Pi RPC client instance
let piClient: PiRpcClient | null = null;
let piProcess: ReturnType<typeof spawn> | null = null;
const connectedClients: Set<WebSocket> = new Set();

// Pi's cwd is fixed at spawn time (RPC has no runtime cwd command), so changing
// the working directory means respawning the Pi child process with a new cwd.
// PI_CWD overrides the directory Pi starts in (useful when running as a service,
// where process.cwd() is the unit's WorkingDirectory).
let currentCwd =
  (process.env.PI_CWD && resolveExistingDir(process.env.PI_CWD)) || process.cwd();

// Directories recently used by Pi sessions, most recent first (deduplicated).
function recentDirectories(): string[] {
  const seen = new Set<string>();
  const dirs: string[] = [];
  for (const session of listPiSessions({ limit: 200 })) {
    if (session.cwd && !seen.has(session.cwd)) {
      seen.add(session.cwd);
      dirs.push(session.cwd);
    }
  }
  return dirs.slice(0, 10);
}

// Initialize Pi RPC client
async function initializePi(cwd: string = currentCwd) {
  if (piClient) return;

  console.log(`Starting Pi in RPC mode (cwd: ${cwd})...`);

  // Spawn Pi process in RPC mode
  // On Windows, "pi" resolves to pi.cmd, which spawn() cannot execute without a shell
  // PI_PROVIDER/PI_MODEL are optional: when unset, Pi starts with its own configured
  // provider/model (pi /login, settings.json, installed provider extensions).
  const args = ["--mode", "rpc"];
  if (process.env.PI_PROVIDER) args.push("--provider", process.env.PI_PROVIDER);
  if (process.env.PI_MODEL) args.push("--model", process.env.PI_MODEL);
  // Sessions are persisted (no --no-session) so /resume can reload them later.
  piProcess = spawn("pi", args, { cwd, shell: process.platform === "win32" });

  const client = new PiRpcClient(piProcess);
  piClient = client;

  // Only clear module state if this client is still the current one — a killed
  // child's late exit event must not clobber a client spawned for a new cwd.
  client.on("error", (err) => {
    console.error("Pi RPC error:", err);
    if (piClient === client) piClient = null;
  });

  client.on("exit", () => {
    console.log("Pi process exited");
    if (piClient === client) {
      piClient = null;
      piProcess = null;
    }
  });

  // Forward all Pi events to connected WebSocket clients
  client.on("event", (event) => {
    for (const wsClient of connectedClients) {
      if (wsClient.readyState === WebSocket.OPEN) {
        wsClient.send(
          JSON.stringify({
            type: "pi_event",
            event,
          })
        );
      }
    }
  });

  console.log("Pi RPC client initialized");
}

// WebSocket connection handler
wss.on("connection", (ws: WebSocket) => {
  console.log("New WebSocket client connected");
  connectedClients.add(ws);

  ws.on("message", async (data: string) => {
    try {
      const message = JSON.parse(data);
      await handleClientMessage(ws, message);
    } catch (err) {
      console.error("Error handling message:", err);
      ws.send(
        JSON.stringify({
          type: "error",
          error: "Failed to process message",
        })
      );
    }
  });

  ws.on("close", () => {
    console.log("WebSocket client disconnected");
    connectedClients.delete(ws);
  });

  ws.on("error", (err) => {
    console.error("WebSocket error:", err);
  });
});

async function handleClientMessage(ws: WebSocket, message: any) {
  const { id, command, ...params } = message;

  // Filesystem browsing does not require a live Pi client.
  if (command === "list_dir") {
    try {
      const requested = params.path
        ? resolveExistingDir(params.path)
        : resolveExistingDir(currentCwd) ?? os.homedir();
      if (!requested) {
        ws.send(
          JSON.stringify({
            type: "response",
            id,
            command,
            success: false,
            error: `Not a directory: ${params.path}`,
          })
        );
        return;
      }
      const listing = listDirectory(requested);
      ws.send(
        JSON.stringify({
          type: "response",
          id,
          command,
          success: true,
          data: {
            ...listing,
            current: currentCwd,
            cwdDisplay: shrinkHome(currentCwd),
            recent: recentDirectories(),
          },
        })
      );
    } catch (err) {
      ws.send(
        JSON.stringify({
          type: "error",
          id,
          command,
          error: (err as Error).message,
        })
      );
    }
    return;
  }

  if (command === "set_cwd") {
    try {
      const target = resolveExistingDir(params.path);
      if (!target) {
        ws.send(
          JSON.stringify({
            type: "response",
            id,
            command,
            success: false,
            error: `Not a directory: ${params.path}`,
          })
        );
        return;
      }
      if (target === currentCwd && piClient) {
        ws.send(
          JSON.stringify({
            type: "response",
            id,
            command,
            success: true,
            data: {
              cwd: currentCwd,
              cwdDisplay: shrinkHome(currentCwd),
              unchanged: true,
            },
          })
        );
        return;
      }
      // Pi's cwd is fixed at spawn time, so restart the child in the new directory.
      if (piProcess) {
        piProcess.kill();
        piProcess = null;
        piClient = null;
      }
      currentCwd = target;
      await initializePi(target);
      ws.send(
        JSON.stringify({
          type: "response",
          id,
          command,
          success: true,
          data: {
            cwd: currentCwd,
            cwdDisplay: shrinkHome(currentCwd),
          },
        })
      );
    } catch (err) {
      ws.send(
        JSON.stringify({
          type: "error",
          id,
          command,
          error: (err as Error).message,
        })
      );
    }
    return;
  }

  if (!piClient) {
    ws.send(
      JSON.stringify({
        type: "error",
        error: "Pi client not initialized",
      })
    );
    return;
  }

  try {
    let response;

    switch (command) {
      case "prompt":
        response = await piClient.prompt(params.message);
        break;
      case "get_state":
        response = await piClient.getState();
        // Pi's RPC state has no cwd; the app needs it to show the current
        // directory in the app bar before anything has been browsed.
        if (response.data) {
          response.data = {
            ...response.data,
            cwd: currentCwd,
            cwdDisplay: shrinkHome(currentCwd),
          };
        }
        break;
      case "get_messages":
        response = await piClient.getMessages();
        break;
      case "abort":
        response = await piClient.abort();
        break;
      case "set_model":
        response = await piClient.setModel(params.model);
        break;
      case "get_available_models":
        response = await piClient.getAvailableModels();
        break;
      case "get_session_stats":
        // Token/cost totals plus context-window usage, used by the app's
        // progress line after a run settles.
        response = await piClient.getSessionStats();
        break;
      case "list_sessions":
        // Pi's own session history, read from its session store on disk.
        response = {
          success: true,
          data: { sessions: listPiSessions({ cwd: params.cwd }) },
        };
        break;
      case "resume_session":
        // Loads a saved session into the live Pi runtime; the client then
        // fetches the history with get_messages.
        response = await piClient.switchSession(params.sessionPath);
        break;
      default:
        ws.send(
          JSON.stringify({
            type: "error",
            id,
            error: `Unknown command: ${command}`,
          })
        );
        return;
    }

    ws.send(
      JSON.stringify({
        type: "response",
        id,
        command,
        success: response.success,
        data: response.data,
        error: response.error,
      })
    );
  } catch (err) {
    console.error(`Error executing command ${command}:`, err);
    ws.send(
      JSON.stringify({
        type: "error",
        id,
        error: (err as Error).message,
      })
    );
  }
}

// HTTP endpoints
app.get("/health", (req, res) => {
  res.json({
    status: "ok",
    pi_connected: !!piClient,
    cwd: currentCwd,
    cwdDisplay: shrinkHome(currentCwd),
  });
});

app.get("/api/models", async (req, res) => {
  try {
    if (!piClient) {
      return res.status(503).json({ error: "Pi not initialized" });
    }
    const response = await piClient.getAvailableModels();
    res.json(response.data);
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get("/api/sessions", (req, res) => {
  try {
    res.json({ sessions: listPiSessions() });
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.get("/api/state", async (req, res) => {
  try {
    if (!piClient) {
      return res.status(503).json({ error: "Pi not initialized" });
    }
    const response = await piClient.getState();
    res.json({
      ...(response.data ?? {}),
      cwd: currentCwd,
      cwdDisplay: shrinkHome(currentCwd),
    });
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

app.post("/api/prompt", async (req, res) => {
  try {
    if (!piClient) {
      return res.status(503).json({ error: "Pi not initialized" });
    }
    const { message } = req.body;
    const response = await piClient.prompt(message);
    res.json({ success: response.success, data: response.data });
  } catch (err) {
    res.status(500).json({ error: (err as Error).message });
  }
});

// Serve the built Flutter web app (frontend/build/web) from this same port so a
// phone on the LAN can open http://<this-machine-ip>:<PORT> in Safari and reach
// the WebSocket on the same origin. Run `npm run build:web` in the repo root
// first; if the folder is absent the API/WebSocket server still works.
const webBuildDir = path.join(import.meta.dirname, "..", "..", "frontend", "build", "web");
app.use(
  express.static(webBuildDir, {
    // Always revalidate so browsers pick up new builds immediately after
    // `npm run build:web` instead of serving a stale cached main.dart.js.
    setHeaders: (res) => {
      res.setHeader("Cache-Control", "no-cache");
    },
  }),
);

const PORT = process.env.PORT || 3000;

server.listen(PORT, async () => {
  console.log(`Server listening on port ${PORT}`);
  console.log(`WebSocket: ws://localhost:${PORT}`);
  console.log(`HTTP API: http://localhost:${PORT}/api`);
  const webBuilt = existsSync(path.join(webBuildDir, "index.html"));
  console.log(webBuilt ? `Web app: serving ${webBuildDir}` : "Web app: not built (run 'flutter build web' in the frontend folder)");

  // Initialize Pi on startup
  await initializePi().catch(console.error);
});

// Graceful shutdown
process.on("SIGINT", () => {
  console.log("Shutting down...");
  piClient?.close();
  server.close(() => {
    console.log("Server closed");
    process.exit(0);
  });
});
