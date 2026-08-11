import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { AppShell } from "./shell/AppShell";
import "./shell/app-shell.css";

const root = document.getElementById("root");

if (root === null) {
  throw new Error("UOK Next shell root element is missing");
}

createRoot(root).render(
  <StrictMode>
    <AppShell />
  </StrictMode>,
);
