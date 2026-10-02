// Tiny build step: copy src/ to dist/ and stamp the build version into the page.
// Kept dependency-free so the image build is fast and has no npm supply-chain surface.
import { cpSync, mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";

const version = process.env.BUILD_VERSION || "dev";
rmSync("dist", { recursive: true, force: true });
mkdirSync("dist", { recursive: true });
cpSync("src", "dist", { recursive: true });
const html = readFileSync("dist/index.html", "utf8").replaceAll("__BUILD_VERSION__", version);
writeFileSync("dist/index.html", html);
console.log(`built frontend ${version}`);
