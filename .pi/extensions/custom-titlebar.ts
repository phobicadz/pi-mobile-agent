/**
 * Custom Title Bar Extension
 *
 * Displays the working directory on the left side and the current git branch
 * on the right side of the header.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { execSync } from "child_process";
import { basename } from "path";

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (ctx.mode === "tui") {
			ctx.ui.setHeader((_tui, theme) => {
				let cachedBranch: string | null = null;
				let lastFetchTime = 0;

				return {
					render(width: number): string[] {
						const now = Date.now();
						// Cache branch info for 5 seconds to avoid excessive git calls
						if (now - lastFetchTime > 5000) {
							try {
								cachedBranch = execSync("git rev-parse --abbrev-ref HEAD", {
									cwd: ctx.cwd,
									encoding: "utf-8",
									timeout: 1000,
									stdio: ["pipe", "pipe", "pipe"],
								})
									.trim()
									.substring(0, 30); // Limit to 30 chars
								lastFetchTime = now;
							} catch {
								cachedBranch = null;
								lastFetchTime = now;
							}
						}

						// Get directory name (basename) and full path
						const dirName = basename(ctx.cwd);
						const dirPath = ctx.cwd;

						// Build the right side (branch info)
						let rightContent = "";
						if (cachedBranch) {
							rightContent = `${theme.fg("accent", "● ")}${theme.fg("muted", cachedBranch)}`;
						}

						// Build the left side (directory)
						const leftContent = `${theme.fg("text", dirName)} ${theme.fg("dim", dirPath)}`;

						// Calculate spacing
						const leftWidth = leftContent.replace(/\x1b\[[0-9;]*m/g, "").length;
						const rightWidth = rightContent.replace(/\x1b\[[0-9;]*m/g, "").length;

						if (leftWidth + rightWidth + 2 > width) {
							// Not enough space, just show directory name
							return [
								theme.fg("text", dirName),
								theme.fg("dim", theme.fg("muted", "keyboard: ? for help")),
							];
						}

						// Calculate padding
						const padding = width - leftWidth - rightWidth;
						const spacer = " ".repeat(Math.max(1, padding));

						return [
							`${leftContent}${spacer}${rightContent}`,
							theme.fg("dim", "keyboard: ? for help"),
						];
					},

					invalidate() {
						// Reset cache on invalidate to pick up branch changes
						lastFetchTime = 0;
					},
				};
			});
		}
	});
}
