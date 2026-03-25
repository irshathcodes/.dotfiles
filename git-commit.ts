import { ollama } from "npm:ollama-ai-provider-v2@3.5.0";
import { generateText } from "npm:ai@6.0.137";
import { exec as _exec, execFile as _execFile } from "node:child_process";
import { promisify } from "node:util";
import process from "node:process";
const exec = promisify(_exec);
const execFile = promisify(_execFile);

const THRESHOLD = 50_000;

function logAndExit(message: string) {
  console.log(message);
  process.exit();
}

async function getDiff() {
  const filesRes = await exec("git diff --staged --name-only");
  if (filesRes.stderr) logAndExit(filesRes.stderr);

  if (!filesRes.stdout.trim()) {
    logAndExit("You have not staged any files to commit");
  }

  const { stdout, stderr } = await exec(
    `git diff --staged -U0 -- . ':!pnpm-lock.yaml' ':!package-lock.json' ':!yarn.lock'`,
  );

  if (stderr) logAndExit(stderr);

  if (stdout.length > THRESHOLD) {
    console.log(
      "diff exceeding the defined threshold, using the file summary as input",
    );

    const { stdout, stderr } = await exec(
      "git diff --staged --compact-summary",
    );
    if (stderr) logAndExit(stderr);
    return stdout;
  }

  return stdout;
}

const diff = await getDiff();

console.log("Generating commit message...");

const { text: commitMessage } = await generateText({
  model: ollama("qwen3.5:latest"),
  providerOptions: { ollama: { think: false } },
  prompt: diff,
  system:
    "You are a Git commit message generator. Generate commit messages based on the staged file diffs provided as input. If there are lot of staged files then only the file paths with changes will be provided",
});

const { stdout, stderr } = await execFile("git", [
  "commit",
  "-m",
  commitMessage,
]);

if (stderr) logAndExit(stderr);

console.log(stdout);
