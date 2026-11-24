// Entry point of the front, loaded by index.html.
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { NotesScreen } from "./screens/NotesScreen";
import "./styles.css";

const container = document.getElementById("root");
if (container === null) {
  throw new Error("index.html has no element with the id root.");
}

createRoot(container).render(
  <StrictMode>
    <NotesScreen />
  </StrictMode>,
);
