import { mkdirSync, readFileSync, writeFileSync } from "node:fs";

const sourceFile = new URL("../src/codex-radar.js", import.meta.url);
const source = readFileSync(sourceFile, "utf8");
const iconHeader = /^\/\/ Variables used by Scriptable\.\r?\n\/\/ icon-color: ([\w-]+); icon-glyph: ([\w-]+);\r?\n\r?\n/;
const metadata = source.match(iconHeader);
if (!metadata) throw new Error("缺少 Scriptable 图标声明");

const bundle = {
  name: "Codex Radar",
  icon: { color: metadata[1], glyph: metadata[2] },
  always_run_in_app: false,
  share_sheet_inputs: [],
  script: source.slice(metadata[0].length),
};

const outputDir = new URL("../dist/", import.meta.url);
mkdirSync(outputDir, { recursive: true });
writeFileSync(new URL("Codex-Radar.scriptable", outputDir), JSON.stringify(bundle, null, 2) + "\n", "utf8");
console.log("已生成 dist/Codex-Radar.scriptable");
