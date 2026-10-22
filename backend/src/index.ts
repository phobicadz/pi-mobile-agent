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

const app = express();
const server = createServer(app);
const wss = new WebSocketServer({ server });

app.use(cors());
app.use(express.json());

// Global Pi RPC client instance
let piClient: PiRpcClient | null = null;
const connectedClients: Set<WebSocket> = new Set();

// Initialize Pi RPC client
async function initializePi() {
  if (piClient) return;

  console.log("Starting Pi in RPC mode...");

  // Spawn Pi process in RPC mode
  // On Windows, "pi" resolves to pi.cmd, which spawn() cannot execute without a shell
  const provider = process.env.PI_PROVIDER || "github-copilot";
  const model = process.env.PI_MODEL || "claude-sonnet-5";
  // Sessions are persisted (no --no-session) so /resume can reload them later.
  const piProcess = spawn("pi", [
    "--mode",
    "rpc",
    "--provider",
    provider,
    "--model",
    model,
  ], { shell: process.platform === "win32" });

  piClient = new PiRpcClient(piProcess);

  piClient.on("error", (err) => {
    console.error("Pi RPC error:", err);
    piClient = null;
  });

  piClient.on("exit", () => {
    console.log("Pi process exited");
    piClient = null;
  });

  // Forward all Pi events to connected WebSocket clients
  piClient.on("event", (event) => {
    connectedClients.forEach((client) => {
      if (client.readyState === WebSocket.OPEN) {
        client.send(
          JSON.stringify({
            type: "pi_event",
            event,
          })
        );
      }
    });
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
  if (!piClient) {
    ws.send(
      JSON.stringify({
        type: "error",
        error: "Pi client not initialized",
      })
    );
    return;
  }

  const { id, command, ...params } = message;

  try {
    let response;

    switch (command) {
      case "prompt":
        response = await piClient.prompt(params.message);
        break;
      case "get_state":
        response = await piClient.getState();
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
  res.json({ status: "ok", pi_connected: !!piClient });
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
    res.json(response.data);
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
