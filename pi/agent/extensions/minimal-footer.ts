import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { isAbsolute, relative, resolve, sep } from "node:path";

function formatTokens(count: number | null | undefined): string {
	if (count == null) return "?";
	if (count < 1000) return count.toString();
	if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
	if (count < 1000000) return `${Math.round(count / 1000)}k`;
	if (count < 10000000) return `${(count / 1000000).toFixed(1)}M`;
	return `${Math.round(count / 1000000)}M`;
}

function formatCwd(cwd: string): string {
	const home = process.env.HOME || process.env.USERPROFILE;
	if (!home) return cwd;

	const resolvedCwd = resolve(cwd);
	const resolvedHome = resolve(home);
	const relativeToHome = relative(resolvedHome, resolvedCwd);
	const insideHome =
		relativeToHome === "" ||
		(relativeToHome !== ".." && !relativeToHome.startsWith(`..${sep}`) && !isAbsolute(relativeToHome));

	return insideHome ? (relativeToHome === "" ? "~" : `~${sep}${relativeToHome}`) : cwd;
}

function stripAnsi(text: string): string {
	return text.replace(/\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])/g, "");
}

function sanitizeStatusText(text: string): string {
	return stripAnsi(text).replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim();
}

function shouldShowStatus(text: string): boolean {
	// Hide disconnected MCP status, e.g. "MCP: 0/1 servers".
	// Match loosely because extension status text may vary slightly.
	return !/^MCP:\s*0\s*\/\s*\d+\b/i.test(text);
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setFooter((tui, theme, footerData) => {
			const unsubscribe = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose: unsubscribe,
				invalidate() {},
				render(width: number): string[] {
					const branch = footerData.getGitBranch();
					const cwd = `${formatCwd(ctx.cwd)}${branch ? ` (${branch})` : ""}`;

					const usage = ctx.getContextUsage();
					const contextWindow = usage?.contextWindow ?? ctx.model?.contextWindow;
					const contextText = `${formatTokens(usage?.tokens)}/${formatTokens(contextWindow)}`;

					const thinking = pi.getThinkingLevel();
					const model = ctx.model ? `${ctx.model.id}${ctx.model.reasoning ? ` • ${thinking}` : ""}` : "no-model";

					const statuses = Array.from(footerData.getExtensionStatuses().entries())
						.sort(([a], [b]) => a.localeCompare(b))
						.map(([, text]) => sanitizeStatusText(text))
						.filter(shouldShowStatus);

					const leftRaw = [cwd, contextText, ...statuses].filter(Boolean).join(" · ");
					const rightRaw = model;
					const minPadding = 2;
					const availableLeft = Math.max(0, width - visibleWidth(rightRaw) - minPadding);

					if (availableLeft <= 0) {
						return [theme.fg("dim", truncateToWidth(leftRaw, width, "..."))];
					}

					const left = truncateToWidth(leftRaw, availableLeft, "...");
					const padding = " ".repeat(Math.max(minPadding, width - visibleWidth(left) - visibleWidth(rightRaw)));

					return [theme.fg("dim", left) + padding + theme.fg("dim", rightRaw)];
				},
			};
		});
	});
}
