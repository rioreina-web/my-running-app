import { defineConfig } from "sanity";
import { structureTool } from "sanity/structure";
import { visionTool } from "@sanity/vision";
import { schemaTypes } from "./schemas";
import { sanityConfig } from "./config";

export default defineConfig({
  name: "post-run-drip",
  title: "Post Run Drip",
  ...sanityConfig,
  plugins: [structureTool(), visionTool()],
  schema: {
    types: schemaTypes,
  },
});
