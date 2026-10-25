import * as net from "net";
import * as readline from "readline";
import { EventEmitter } from "events";
import { Duplex } from "stream";

export interface RpcCommand {
  id?: string;
  type: string;
  [key: string]: unknown;
}

export interface RpcResponse {
  id?: string;
  type: "response";
  command: string;
  success: boolean;
  data?: unknown;
  error?: string;
}

export interface RpcEvent {
  type: string;
  [key: string]: unknown;
}

export class PiRpcClient extends EventEmitter {
  private child: any;
  private rl: readline.Interface;
  private requestId = 0;
  private pendingRequests: Map<string, (response: RpcResponse) => void> =
    new Map();

  constructor(child: any) {
    super();
    this.child = child;

    // Create readline interface for stdout
    this.rl = readline.createInterface({
      input: child.stdout,
      crlfDelay: Infinity,
    });

    // Handle each line from Pi
    this.rl.on("line", (line) => {
      try {
        const record = JSON.parse(line);
        this.handleRecord(record);
      } catch (e) {
        console.error("Failed to parse RPC response:", line, e);
      }
    });

    // Handle errors
    child.on("error", (err: Error) => this.emit("error", err));
    child.on("exit", () => this.emit("exit"));
  }

  private handleRecord(record: any) {
    if (record.type === "response") {
      // Handle command response
      const id = record.id;
      if (id && this.pendingRequests.has(id)) {
        const resolve = this.pendingRequests.get(id)!;
        this.pendingRequests.delete(id);
        resolve(record);
      }
    }

    // Emit all events (session events, message updates, etc.)
    this.emit("event", record);
  }

  async sendCommand(command: RpcCommand): Promise<RpcResponse> {
    return new Promise((resolve, reject) => {
      const id = `${Date.now()}-${++this.requestId}`;
      command.id = id;

      this.pendingRequests.set(id, resolve);

      // Timeout after 30 seconds
      setTimeout(() => {
        if (this.pendingRequests.has(id)) {
          this.pendingRequests.delete(id);
          reject(new Error(`Command timeout: ${command.type}`));
        }
      }, 30000);

      const json = JSON.stringify(command) + "\n";
      this.child.stdin.write(json, (err: Error | null) => {
        if (err) reject(err);
      });
    });
  }

  async prompt(message: string): Promise<RpcResponse> {
    return this.sendCommand({
      type: "prompt",
      message,
    });
  }

  async getState(): Promise<RpcResponse> {
    return this.sendCommand({
      type: "get_state",
    });
  }

  async getMessages(): Promise<RpcResponse> {
    return this.sendCommand({
      type: "get_messages",
      limit: 100,
    });
  }

  async abort(): Promise<RpcResponse> {
    return this.sendCommand({
      type: "abort",
    });
  }

  async setModel(model: string): Promise<RpcResponse> {
    return this.sendCommand({
      type: "set_model",
      model,
    });
  }

  async getAvailableModels(): Promise<RpcResponse> {
    return this.sendCommand({
      type: "get_available_models",
    });
  }

  /** Session token totals, cost and current context-window usage. */
  async getSessionStats(): Promise<RpcResponse> {
    return this.sendCommand({
      type: "get_session_stats",
    });
  }

  async switchSession(sessionPath: string): Promise<RpcResponse> {
    return this.sendCommand({
      type: "switch_session",
      sessionPath,
    });
  }

  close() {
    this.child.stdin.end();
    this.rl.close();
  }
}

export default PiRpcClient;
