<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import {
    Search,
    User,
    Settings,
    Minus,
    Maximize2,
    Minimize2,
    X,
    Library,
    Calendar,
  } from "@lucide/svelte";
  import {
    WindowMinimise,
    WindowIsMaximised,
    WindowUnmaximise,
    WindowMaximise,
    Quit,
  } from "$wails/runtime/runtime";

  let {
    searchQuery = $bindable(""),
    isLoggedIn = false,
    onSearch,
    onHome,
    onLogin,
    onSettings,
    onWatchlist,
    onScheduled,
  } = $props();

  let isMaximised = $state(false);

  async function syncMaximisedState() {
    isMaximised = await WindowIsMaximised();
  }

  onMount(async () => {
    await syncMaximisedState();
    window.addEventListener("resize", syncMaximisedState);
  });

  onDestroy(() => {
    window.removeEventListener("resize", syncMaximisedState);
  });

  async function handleWindowMaximise() {
    if (await WindowIsMaximised()) {
      WindowUnmaximise();
      isMaximised = false;
    } else {
      WindowMaximise();
      isMaximised = true;
    }
  }
</script>

<nav
  style="--wails-draggable: drag;"
  class="sticky top-0 z-50 bg-base border-b border-border px-6 py-4 flex items-center justify-between"
>
  <button
    style="--wails-draggable: no-drag;"
    onclick={onHome}
    class="flex items-center space-x-2 text-primary hover:text-primary-hover transition-colors
           focus:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded px-2 py-1 -ml-2 group"
  >
    <h1
      class="text-xl font-bold tracking-tight text-main group-hover:text-white transition-colors"
    >
      AniStream
    </h1>
  </button>

  <div class="flex-1 max-w-2xl px-8">
    <div class="relative group">
      <div
        class="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none
               text-muted group-focus-within:text-primary transition-colors"
      >
        <Search size={20} />
      </div>
      <input
        style="--wails-draggable: no-drag;"
        type="text"
        bind:value={searchQuery}
        oninput={() => onSearch?.()}
        placeholder="Search for anime by title..."
        class="w-full bg-surface border border-border text-main text-sm rounded-full
               focus:ring-2 focus:ring-primary focus:border-primary block pl-11 p-2.5
               transition-all shadow-inner outline-none"
      />
    </div>
  </div>

  <div class="flex items-center space-x-4 text-muted">
    <button
      style="--wails-draggable: no-drag;"
      onclick={onScheduled}
      class="hover:text-primary transition-colors focus:outline-none
               focus-visible:ring-2 focus-visible:ring-primary rounded-full p-1"
      title="Scheduled"
    >
      <Calendar size={20} />
    </button>
    {#if isLoggedIn}
      <button
        style="--wails-draggable: no-drag;"
        onclick={onWatchlist}
        class="hover:text-primary transition-colors focus:outline-none
               focus-visible:ring-2 focus-visible:ring-primary rounded-full p-1"
        title="My Watchlist"
      >
        <Library size={20} />
      </button>
    {/if}

    <button
      style="--wails-draggable: no-drag;"
      onclick={onLogin}
      class="focus:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded-full p-1 transition-colors
             {isLoggedIn
        ? 'text-green-400 hover:text-red-400'
        : 'text-muted hover:text-main'}"
      title={isLoggedIn ? "Log out of AniList" : "Log in to AniList"}
    >
      <User size={20} />
    </button>

    <button
      style="--wails-draggable: no-drag;"
      onclick={onSettings}
      class="hover:text-main transition-colors focus:outline-none
             focus-visible:ring-2 focus-visible:ring-primary rounded-full p-1"
      title="Settings"
    >
      <Settings size={20} />
    </button>

    <div class="flex items-center space-x-2 border-l border-border pl-4">
      <button
        style="--wails-draggable: no-drag;"
        onclick={WindowMinimise}
        class="hover:text-main transition-colors"
      >
        <Minus size={20} />
      </button>
      <button
        style="--wails-draggable: no-drag;"
        onclick={handleWindowMaximise}
        class="hover:text-accent transition-colors"
      >
        {#if isMaximised}<Minimize2 size={20} />{:else}<Maximize2
            size={20}
          />{/if}
      </button>
      <button
        style="--wails-draggable: no-drag;"
        onclick={Quit}
        class="hover:text-red-400 transition-colors"
      >
        <X size={20} />
      </button>
    </div>
  </div>
</nav>
