import { readFileSync, writeFileSync } from "node:fs";
import { zipSync } from "fflate";

// A fixed local time keeps the archive byte-identical between builds.
const mtime = new Date(1980, 0, 1);

writeFileSync(
	"dist/renderer.zip",
	zipSync({ "index.js": [readFileSync("dist/index.js"), { mtime, level: 9 }] }),
);
