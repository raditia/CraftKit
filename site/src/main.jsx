import React from "react";
import { createRoot, hydrateRoot } from "react-dom/client";
import "@fontsource-variable/inter";
import { App } from "./App.jsx";
import "./styles.css";

const root = document.getElementById("root");
const app = (
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
// The build prerenders the markup (scripts/prerender.mjs); `vite dev` serves an empty root.
if (root.hasChildNodes()) hydrateRoot(root, app);
else createRoot(root).render(app);
