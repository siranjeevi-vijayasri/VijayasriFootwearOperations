import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals.js";
import nextTypescript from "eslint-config-next/typescript.js";

const asConfigArray = value => Array.isArray(value) ? value : [value];

const eslintConfig = defineConfig([
  ...asConfigArray(nextVitals),
  ...asConfigArray(nextTypescript),
  globalIgnores([".next/**", "out/**", "build/**", "next-env.d.ts"])
]);

export default eslintConfig;
