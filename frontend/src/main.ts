import { mount } from "svelte";
import "./style.css";
import App from "./App.svelte";

const target = document.getElementById("app");

if (!target) {
  throw new Error("Could not find root element with id 'app'");
}

const app = mount(App, {
  target: target,
});

export default app;
