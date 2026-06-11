import { complete, getModel } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { basename, resolve } from "node:path";

const OSC = "\x1b]";
const ST = "\x1b\\";

const APP_NAME_BASE64 = "cGktY29kaW5nLWFnZW50"; // pi-coding-agent
const NOTIFICATION_TYPE_BASE64 = "bGxtLXJlYWR5"; // llm-ready
const ICON_NAME_BASE64 = "dXRpbGl0aWVzLXRlcm1pbmFs"; // utilities-terminal
const EXPIRE_AFTER_MS = 10_000;
const MAX_BODY_CHARS = 220;
const MAX_TITLE_CHARS = 58;
const TITLE_MODEL_PROVIDER = "openai-codex";
const TITLE_MODEL_ID = "gpt-5.5";

const notificationReportPattern = /\x1b\]99;([^\x07\x1b;]*);([^\x07\x1b]*)(?:\x1b\\|\x07)/g;

type KittyWindow = {
	id?: number;
	is_self?: boolean;
	is_active?: boolean;
	is_focused?: boolean;
};

type KittyTab = {
	is_active?: boolean;
	is_focused?: boolean;
	windows?: KittyWindow[];
};

type KittyOsWindow = {
	is_active?: boolean;
	is_focused?: boolean;
	tabs?: KittyTab[];
};

function base64(text: string): string {
	return Buffer.from(text, "utf8").toString("base64");
}

function projectName(cwd: string): string {
	return basename(resolve(cwd)) || cwd;
}

function truncateText(text: string, maxChars = MAX_BODY_CHARS): string {
	const chars = Array.from(text);
	return chars.length > maxChars ? `${chars.slice(0, maxChars - 1).join("")}…` : text;
}

function stripAnsi(text: string): string {
	return text.replace(/\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])/g, "");
}

function normalizeTitleText(text: string): string {
	return stripAnsi(text)
		.replace(/```[\s\S]*?```/g, "code")
		.replace(/[`*_~#>\[\]{}()]/g, " ")
		.replace(/\s+/g, " ")
		.trim();
}

function titleFromSummary(summary: string, cwd: string): string {
	const project = projectName(cwd);
	const title = truncateText(normalizeTitleText(summary).replace(/^['"]|['"]$/g, "") || "new chat", MAX_TITLE_CHARS);
	return `π · ${title} · ${project}`;
}

function fallbackTitleFromPrompt(prompt: string, cwd: string): string {
	const words = normalizeTitleText(prompt).split(" ").filter(Boolean).slice(0, 8).join(" ");
	return titleFromSummary(words || "new chat", cwd);
}

function baseTitle(pi: ExtensionAPI, cwd: string): string {
	const project = projectName(cwd);
	const session = pi.getSessionName?.();
	return session ? `π · ${session} · ${project}` : `π · ${project}`;
}

function titlePrompt(userPrompt: string): string {
	return `Generate a concise terminal window title for this new coding-agent chat.\n\nRules:\n- 3 to 6 words.\n- No quotes.\n- No punctuation unless necessary.\n- Title Case is OK.\n- Return only the title.\n\nUser message:\n${userPrompt}`;
}

async function generateTitleWithCheapModel(modelRegistry: { getApiKeyAndHeaders: (model: any) => Promise<{ ok: boolean; apiKey?: string; headers?: Record<string, string>; error?: string }> }, cwd: string, userPrompt: string): Promise<string | undefined> {
	const model = getModel(TITLE_MODEL_PROVIDER, TITLE_MODEL_ID);
	if (!model) return undefined;

	const auth = await modelRegistry.getApiKeyAndHeaders(model);
	if (!auth.ok || !auth.apiKey) return undefined;

	const response = await complete(
		model,
		{
			messages: [
				{
					role: "user" as const,
					content: [{ type: "text" as const, text: titlePrompt(userPrompt) }],
					timestamp: Date.now(),
				},
			],
		},
		{ apiKey: auth.apiKey, headers: auth.headers, maxTokens: 20 },
	);

	const title = response.content
		.filter((c): c is { type: "text"; text: string } => c.type === "text")
		.map((c) => c.text)
		.join(" ");
	return title.trim() ? titleFromSummary(title, cwd) : undefined;
}

function notificationTextFromMessage(message: any): string {
	const content = message?.content;
	if (typeof content === "string") return content;
	if (!Array.isArray(content)) return "";

	return content
		.map((part) => {
			if (typeof part === "string") return part;

			// Keep only assistant answer text. Desktop notifications should summon
			// the user, not leak thinking, tool calls, images, or raw transcripts.
			if (part?.type === "text" && typeof part.text === "string") return part.text;
			return "";
		})
		.join("")
		.trim();
}

function compactForNotification(text: string): string {
	return truncateText(
		stripAnsi(text)
			.replace(/```[\s\S]*?```/g, "[code omitted]")
			.replace(/`([^`]+)`/g, "$1")
			.replace(/\[([^\]]+)]\([^)]+\)/g, "$1")
			.replace(/\s+/g, " ")
			.trim(),
	);
}

function lastAssistantText(messages: any[]): string {
	for (let i = messages.length - 1; i >= 0; i--) {
		const message = messages[i];
		if (message?.role !== "assistant") continue;
		const text = compactForNotification(notificationTextFromMessage(message));
		if (text) return text;
	}
	return "Pi is ready for input.";
}

function parseMetadata(metadata: string): Record<string, string> {
	const parsed: Record<string, string> = {};
	for (const part of metadata.split(":")) {
		const separator = part.indexOf("=");
		if (separator <= 0) continue;
		parsed[part.slice(0, separator)] = part.slice(separator + 1);
	}
	return parsed;
}

function notificationId(): string {
	const windowId = process.env.KITTY_WINDOW_ID?.replace(/[^a-zA-Z0-9_.+-]/g, "") || "no-window";
	return `pi-${process.pid}-${windowId}`;
}

function isKittyInteractiveTerminal(): boolean {
	return !!process.env.KITTY_WINDOW_ID && process.stdout.isTTY;
}

function setKittyLoadingFlag(pi: ExtensionAPI, loading: boolean): void {
	const windowId = process.env.KITTY_WINDOW_ID;
	if (!windowId) return;

	void pi
		.exec("kitty", ["@", "set-user-vars", "--match", `id:${windowId}`, `loading=${loading ? "true" : "false"}`], { timeout: 1000 })
		.catch(() => {
			// Picker also detects the title spinner. User vars are a nicer explicit
			// signal when remote control is available, but not required.
		});
}

function focusCurrentKittyWindow(pi: ExtensionAPI): void {
	const windowId = process.env.KITTY_WINDOW_ID;
	if (!windowId) return;

	void pi
		.exec("kitty", ["@", "focus-window", "--match", `id:${windowId}`, "--no-response"], { timeout: 1000 })
		.catch(() => {
			// The OSC 99 focus action is the primary mechanism. This remote-control
			// call is only an extra guard for stack layouts/sessions, so ignore errors.
		});
}

async function getKittyWindowFocused(pi: ExtensionAPI): Promise<boolean | undefined> {
	const targetWindowId = Number(process.env.KITTY_WINDOW_ID);
	if (!Number.isFinite(targetWindowId)) return undefined;

	try {
		const result = await pi.exec("kitty", ["@", "ls", "--self"], { timeout: 1000 });
		if (result.code !== 0 || !result.stdout.trim()) return undefined;

		const osWindows = JSON.parse(result.stdout) as KittyOsWindow[];
		for (const osWindow of osWindows) {
			for (const tab of osWindow.tabs ?? []) {
				for (const window of tab.windows ?? []) {
					if (!window.is_self && window.id !== targetWindowId) continue;

					const osFocused = osWindow.is_focused ?? osWindow.is_active;
					const tabFocused = tab.is_focused ?? tab.is_active;
					const windowFocused = window.is_focused ?? window.is_active;
					return osFocused === true && tabFocused === true && windowFocused === true;
				}
			}
		}
	} catch {
		// Fall back to Kitty's own o=unfocused protocol guard in the notification.
	}

	return undefined;
}

function writeKittyNotification(title: string, body: string, options?: { force?: boolean; id?: string }): string | undefined {
	if (!isKittyInteractiveTerminal()) return undefined;

	const id = options?.id ?? notificationId();
	const occasion = options?.force ? "always" : "unfocused";
	const commonMetadata = [
		`i=${id}`,
		"a=focus,report",
		`o=${occasion}`,
		`f=${APP_NAME_BASE64}`,
		`t=${NOTIFICATION_TYPE_BASE64}`,
		`n=${ICON_NAME_BASE64}`,
		"u=1",
		`w=${EXPIRE_AFTER_MS}`,
	];

	// OSC 99 is chunked: first send title with d=0, then body with d=1.
	// Payloads are base64 encoded so titles/bodies may contain newlines or emoji.
	process.stdout.write(`${OSC}99;${[...commonMetadata, "d=0", "e=1"].join(":")};${base64(title)}${ST}`);
	process.stdout.write(`${OSC}99;${[...commonMetadata, "p=body", "d=1", "e=1"].join(":")};${base64(body)}${ST}`);

	return id;
}

export default function (pi: ExtensionAPI) {
	const activeNotificationIds = new Set<string>();
	const cleanupTimers = new Set<ReturnType<typeof setTimeout>>();
	let unsubscribeTerminalInput: (() => void) | undefined;
	let sessionTitle: string | undefined;
	let titleWasRequested = false;
	let titleRequestId = 0;

	function rememberNotification(id: string): void {
		activeNotificationIds.add(id);
		const timer = setTimeout(() => {
			activeNotificationIds.delete(id);
			cleanupTimers.delete(timer);
		}, EXPIRE_AFTER_MS + 60_000);
		cleanupTimers.add(timer);
	}

	function handleNotificationReport(metadataText: string, payload: string): boolean {
		const metadata = parseMetadata(metadataText);
		const id = metadata.i;
		if (!id || !activeNotificationIds.has(id)) return false;

		if (metadata.p === "close") {
			activeNotificationIds.delete(id);
			return true;
		}

		// Activation report: <OSC> 99 ; i=<id> ; <ST>
		if (!metadata.p && payload.length === 0) {
			focusCurrentKittyWindow(pi);
			activeNotificationIds.delete(id);
			return true;
		}

		return true;
	}

	function installTerminalInputHandler(ctx: { hasUI: boolean; ui: { onTerminalInput: (handler: (data: string) => { consume?: boolean; data?: string } | undefined) => () => void } }): void {
		if (unsubscribeTerminalInput || !ctx.hasUI) return;

		unsubscribeTerminalInput = ctx.ui.onTerminalInput((data) => {
			let handled = false;
			const rewritten = data.replace(notificationReportPattern, (_sequence, metadata: string, payload: string) => {
				if (!handleNotificationReport(metadata, payload)) return _sequence;
				handled = true;
				return "";
			});

			if (!handled) return undefined;
			return rewritten.length === 0 ? { consume: true } : { data: rewritten };
		});
	}

	function disposeTerminalInputHandler(): void {
		unsubscribeTerminalInput?.();
		unsubscribeTerminalInput = undefined;
	}

	pi.on("session_start", async (_event, ctx) => {
		installTerminalInputHandler(ctx);
		sessionTitle = baseTitle(pi, ctx.cwd);
		titleWasRequested = false;
		titleRequestId++;
		ctx.ui.setTitle(sessionTitle);
		setKittyLoadingFlag(pi, false);
	});

	pi.on("before_agent_start", async (event, ctx) => {
		if (titleWasRequested || !event.prompt?.trim()) return;

		titleWasRequested = true;
		const requestId = ++titleRequestId;
		const cwd = ctx.cwd;
		const prompt = event.prompt;

		// Set an immediate usable title, then ask a cheap model out-of-band. This
		// separate completion is not appended to the Pi session or current context.
		sessionTitle = fallbackTitleFromPrompt(prompt, cwd);
		ctx.ui.setTitle(sessionTitle);

		void generateTitleWithCheapModel(ctx.modelRegistry, cwd, prompt)
			.then((generatedTitle) => {
				if (!generatedTitle || requestId !== titleRequestId) return;
				sessionTitle = generatedTitle;
				ctx.ui.setTitle(sessionTitle);
			})
			.catch(() => {
				// Keep the fallback title if OpenAI auth/model/network is unavailable.
			});
	});

	pi.on("agent_start", async (_event, ctx) => {
		setKittyLoadingFlag(pi, true);
		if (sessionTitle) ctx.ui.setTitle(`⠋ ${sessionTitle}`);
	});

	pi.on("session_shutdown", async (_event, ctx) => {
		if (sessionTitle) ctx.ui.setTitle(sessionTitle);
		setKittyLoadingFlag(pi, false);
		disposeTerminalInputHandler();
		for (const timer of cleanupTimers) clearTimeout(timer);
		cleanupTimers.clear();
		activeNotificationIds.clear();
	});

	pi.on("agent_end", async (event, ctx) => {
		setKittyLoadingFlag(pi, false);
		if (sessionTitle) ctx.ui.setTitle(sessionTitle);
		if (!isKittyInteractiveTerminal()) return;

		// If steering/follow-up messages are queued, wait until Pi is truly idle.
		if (ctx.hasPendingMessages()) return;

		// If remote control can prove this exact Kitty window is focused, skip.
		// Otherwise still emit with o=unfocused so Kitty itself suppresses focused windows,
		// including the active split in stack layouts.
		if ((await getKittyWindowFocused(pi)) === true) return;

		const project = projectName(ctx.cwd);
		const title = `${project} · Pi ready`;
		const body = lastAssistantText(event.messages as any[]);
		const id = writeKittyNotification(title, body, { id: notificationId() });
		if (id) rememberNotification(id);
	});

	pi.registerCommand("kitty-notify-test", {
		description: "Send a test Kitty desktop notification for this Pi window",
		handler: async (_args, ctx) => {
			if (!isKittyInteractiveTerminal()) {
				ctx.ui.notify("Kitty desktop notification test requires an interactive Kitty window.", "error");
				return;
			}

			const project = projectName(ctx.cwd);
			const id = writeKittyNotification(`${project} · Pi notification test`, "Click this notification to focus the originating Kitty window/split.", {
				force: true,
				id: `${notificationId()}-test`,
			});
			if (id) {
				rememberNotification(id);
				ctx.ui.notify("Kitty desktop notification sent.", "info");
			} else {
				ctx.ui.notify("Kitty desktop notification could not be sent.", "error");
			}
		},
	});
}
