import { homedir } from "node:os";
import { join, resolve } from "node:path";
import type { SkillSource } from "../types.ts";

export interface SkillRoot {
  path: string;
  source: SkillSource;
}

export function getAgentDir(): string {
  const configured = process.env.PI_CODING_AGENT_DIR?.trim();
  if (configured) return expandHome(configured);
  return join(homedir(), ".pi", "agent");
}

export function getSkillRoots(cwd: string): SkillRoot[] {
  const resolvedCwd = resolve(cwd);
  const agentSkills = join(getAgentDir(), "skills");
  const homeAgentSkills = join(homedir(), ".agents", "skills");
  const roots: SkillRoot[] = [
    {
      path: agentSkills,
      source: { kind: "user", root: agentSkills },
    },
    // Pi also loads global Agent Skills from ~/.agents/skills. The upstream
    // extension copy missed this location, which made /toggle-skills show
    // "No skills found" for our current setup.
    {
      path: homeAgentSkills,
      source: { kind: "user", root: homeAgentSkills },
    },
    {
      path: resolve(resolvedCwd, ".pi", "skills"),
      source: { kind: "project", root: resolve(resolvedCwd, ".pi", "skills") },
    },
  ];

  // Pi discovers project .agents/skills in cwd and ancestors. Mirror that enough
  // for normal dotfiles/project usage so the toggle UI sees the same local skills.
  for (const ancestor of getAncestors(resolvedCwd)) {
    const legacySkills = resolve(ancestor, ".agents", "skills");
    roots.push({
      path: legacySkills,
      source: { kind: "project-legacy", root: legacySkills },
    });
  }

  const seen = new Set<string>();
  return roots.filter((root) => {
    const key = resolve(root.path);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

function getAncestors(start: string): string[] {
  const ancestors: string[] = [];
  let current = start;

  while (true) {
    ancestors.push(current);
    const parent = resolve(current, "..");
    if (parent === current) return ancestors;
    current = parent;
  }
}

function expandHome(input: string): string {
  if (input === "~") return homedir();
  if (input.startsWith("~/")) return join(homedir(), input.slice(2));
  return input;
}
