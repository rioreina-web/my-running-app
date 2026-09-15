// Assembles the .dc.html artboards from parts/*.html + parts/common.css.
// Run: node build.mjs   (then seed the canvas from the generated files)
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
const css = readFileSync("parts/common.css", "utf8");
const head = `<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <script src="./support.js"></script>
</head>
<body>
<x-dc>
<helmet>
  <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Crimson+Pro:wght@500;600;700&amp;family=PT+Serif:ital,wght@0,400;0,700;1,400&amp;display=swap">
  <style>
${css}
  </style>
</helmet>
`;
const tail = `
</x-dc>
</body>
</html>
`;
for (const f of readdirSync("parts").filter(f => f.endsWith(".html"))) {
  const name = f.replace(/\.html$/, "");
  writeFileSync(`${name}.dc.html`, head + readFileSync(`parts/${f}`, "utf8") + tail);
  console.log("wrote", `${name}.dc.html`);
}
