<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import {
    LoginWithAniList,
    IsLoggedIn,
    Logout,
    SearchAnime,
    GetTrendingAnime,
  } from "$wails/go/main/App";
  import type { anilist } from "$wails/go/models";

  import NavBar from "$lib/components/layout/NavBar.svelte";
  import SettingsMenu from "$lib/components/layout/SettingsMenu.svelte";

  import DiscoveryView from "./pages/DiscoveryView.svelte";
  import TheaterView from "./pages/TheaterView.svelte";
  import WatchlistView from "./pages/WatchlistView.svelte";

  import { router } from "$lib/stores/router.svelte";

  // ─── Auth state ──────────────────────────────────────────────────────────
  let isUserLoggedIn = $state(false);

  // ─── Settings overlay ────────────────────────────────────────────────────
  let isSettingsOpen = $state(false);

  // ─── Search state ────────────────────────────────────────────────────────
  let searchQuery = $state("");
  let isSearching = $state(false);
  let searchResults = $state<anilist.Anime[]>([]);

  let searchTimeout: ReturnType<typeof setTimeout>;
  let searchGen = 0;

  onMount(async () => {
    try {
      isUserLoggedIn = await IsLoggedIn();
    } catch (err) {
      console.error("Failed to check login status:", err);
    }
    await loadHomePage();
  });

  onDestroy(() => {
    clearTimeout(searchTimeout);
  });

  // ─── Home / trending ─────────────────────────────────────────────────────
  async function loadHomePage(): Promise<void> {
    isSearching = true;
    try {
      searchResults = (await GetTrendingAnime()) || [];
    } catch (err) {
      console.error("Failed to load trending anime:", err);
    } finally {
      isSearching = false;
    }
  }

  // ─── NavBar callbacks ────────────────────────────────────────────────────
  function handleHome(): void {
    router.back();
    searchQuery = "";
    clearTimeout(searchTimeout);
    loadHomePage();
  }

  function handleInput(): void {
    // Typing always navigates back to discovery to show results
    if (router.current.page !== "discovery") router.back();
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(performSearch, 500);
  }

  async function performSearch(): Promise<void> {
    if (searchQuery.length === 0) {
      await loadHomePage();
      return;
    }

    const gen = ++searchGen;
    isSearching = true;
    try {
      const results = await SearchAnime(searchQuery);
      if (gen === searchGen) searchResults = results || [];
    } catch (err) {
      if (gen === searchGen) console.error(err);
    } finally {
      if (gen === searchGen) isSearching = false;
    }
  }

  async function handleLogin(): Promise<void> {
    if (isUserLoggedIn) {
      if (confirm("Are you sure you want to log out of AniList?")) {
        await Logout();
        isUserLoggedIn = false;
        // Boot out of watchlist if we were there
        if (router.current.page === "watchlist") handleHome();
      }
    } else {
      try {
        const result = await LoginWithAniList();
        if (result === "success") isUserLoggedIn = true;
      } catch (err) {
        console.error("OAuth2 failed:", err);
        alert("Failed to log in. Please try again.");
      }
    }
  }
</script>

<main class="min-h-screen flex flex-col bg-base relative">
  <NavBar
    bind:searchQuery
    isLoggedIn={isUserLoggedIn}
    onSearch={handleInput}
    onHome={handleHome}
    onLogin={handleLogin}
    onSettings={() => (isSettingsOpen = true)}
    onWatchlist={() => router.navigate({ page: "watchlist" })}
  />

  <!-- ─── Router outlet ─────────────────────────────────────────────────── -->
  {#if router.current.page === "theater"}
    <TheaterView
      anime={router.current.anime}
      isLoggedIn={isUserLoggedIn}
      onBack={router.back}
    />
  {:else if router.current.page === "watchlist"}
    <WatchlistView
      onSelectAnime={(anime) => router.navigate({ page: "theater", anime })}
    />
  {:else}
    <!-- discovery is the default/fallback -->
    <DiscoveryView
      {searchQuery}
      {isSearching}
      {searchResults}
      onSelect={(anime) => router.navigate({ page: "theater", anime })}
    />
  {/if}

  {#if isSettingsOpen}
    <SettingsMenu onClose={() => (isSettingsOpen = false)} />
  {/if}
</main>
