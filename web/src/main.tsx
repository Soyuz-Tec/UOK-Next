import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { Gate3Application } from "./application/Gate3Application";
import { AppShell } from "./shell/AppShell";
import "./shell/app-shell.css";
import "./modules/master-parties/party-onboarding.css";

const root = document.getElementById("root");

if (root === null) {
  throw new Error("UOK Next shell root element is missing");
}

createRoot(root).render(
  <StrictMode>
    <AppShell>
      <Gate3Application />
    </AppShell>
  </StrictMode>,
);
