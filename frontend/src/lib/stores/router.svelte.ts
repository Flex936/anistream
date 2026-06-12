import type { anilist } from "$wails/go/models";

// ─── Discriminated union of every top-level route ─────────────────────────
export type Route =
  | { page: "discovery" }
  | { page: "theater"; anime: anilist.Anime }
  | { page: "watchlist" };

// ─── Closure-based singleton (works in .svelte.ts files) ──────────────────
function createRouter() {
  let current = $state<Route>({ page: "discovery" });

  return {
    get current(): Route {
      return current;
    },
    navigate(route: Route): void {
      current = route;
    },
    back(): void {
      current = { page: "discovery" };
    },
  };
}

export const router = createRouter();
