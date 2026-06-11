import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const SETTINGS_PATH = join(homedir(), ".pi/agent/settings.json");
const SUBAGENTS_SOURCE = "npm:pi-subagents";

type PackageEntry = string | {
	source?: string;
	extensions?: string[];
	skills?: string[];
	prompts?: string[];
	themes?: string[];
	[key: string]: unknown;
};

type Settings = {
	packages?: PackageEntry[];
	[key: string]: unknown;
};

function readSettings(): Settings {
	if (!existsSync(SETTINGS_PATH)) return {};
	return JSON.parse(readFileSync(SETTINGS_PATH, "utf8"));
}

function writeSettings(settings: Settings): void {
	writeFileSync(SETTINGS_PATH, `${JSON.stringify(settings, null, 2)}\n`);
}

function isSubagentsEntry(entry: PackageEntry): boolean {
	return entry === SUBAGENTS_SOURCE || (typeof entry === "object" && entry?.source === SUBAGENTS_SOURCE);
}

function isEnabled(settings: Settings): boolean {
	return (settings.packages ?? []).some((entry) => entry === SUBAGENTS_SOURCE);
}

function disabledEntry(): PackageEntry {
	return {
		source: SUBAGENTS_SOURCE,
		extensions: [],
		skills: [],
		prompts: [],
	};
}

function setSubagentsEnabled(enabled: boolean): boolean {
	const settings = readSettings();
	const packages = Array.isArray(settings.packages) ? settings.packages : [];
	const wasEnabled = isEnabled(settings);
	const withoutSubagents = packages.filter((entry) => !isSubagentsEntry(entry));

	settings.packages = enabled
		? [...withoutSubagents, SUBAGENTS_SOURCE]
		: [...withoutSubagents, disabledEntry()];

	writeSettings(settings);
	return wasEnabled !== enabled;
}

export default function (pi: ExtensionAPI) {
	pi.registerCommand("subagents-on", {
		description: "Enable pi-subagents package resources and reload Pi",
		handler: async (_args, ctx) => {
			const changed = setSubagentsEnabled(true);
			ctx.ui.notify(changed ? "Enabled pi-subagents. Reloading..." : "pi-subagents already enabled. Reloading...", "info");
			await ctx.reload();
			return;
		},
	});

	pi.registerCommand("subagents-off", {
		description: "Disable pi-subagents package resources and reload Pi",
		handler: async (_args, ctx) => {
			const changed = setSubagentsEnabled(false);
			ctx.ui.notify(changed ? "Disabled pi-subagents. Reloading..." : "pi-subagents already disabled. Reloading...", "info");
			await ctx.reload();
			return;
		},
	});

	pi.registerCommand("subagents-status", {
		description: "Show whether pi-subagents is enabled in global Pi settings",
		handler: async (_args, ctx) => {
			const settings = readSettings();
			ctx.ui.notify(isEnabled(settings) ? "pi-subagents is enabled" : "pi-subagents is disabled", "info");
			return;
		},
	});
}
