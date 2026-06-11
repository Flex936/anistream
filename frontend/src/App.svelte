<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { LoginWithAniList, IsLoggedIn, Logout } from "../wailsjs/go/main/App";
  import { SearchAnime, GetTrendingAnime } from "../wailsjs/go/main/App";
  import type { main } from "../wailsjs/go/models";

  import NavBar from "./components/layout/NavBar.svelte";
  import SettingsMenu from "./components/layout/SettingsMenu.svelte";
  import DiscoveryView from "./pages/DiscoveryView.svelte";
  import TheaterView from "./pages/TheaterView.svelte";
  import Watchlist from "./pages/Watchlist.svelte";

  let searchQuery = $state("");
  let isSearching = $state(false);
  let searchResults = $state<main.Anime[]>([]);
  let isUserLoggedIn = $state(false);
  let isSettingsOpen = $state(false);

  let currentView = $state<"discovery" | "watchlist">("discovery");
  let selectedAnime = $state<main.Anime | null>(null);

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

  async function loadHomePage() {
    isSearching = true;
    try {
      const results = await GetTrendingAnime();
      searchResults = results || [];
    } catch (error) {
      console.error("Failed to load trending anime:", error);
    } finally {
      isSearching = false;
    }
  }

  function handleHome() {
    selectedAnime = null;
    currentView = "discovery"; // Reset view
    searchQuery = "";
    clearTimeout(searchTimeout);
    loadHomePage();
  }

  async function performSearch() {
    if (searchQuery.length === 0) {
      await loadHomePage();
      return;
    }

    const gen = ++searchGen;
    isSearching = true;
    try {
      const results = await SearchAnime(searchQuery);
      // Only commit results if no newer search has been issued
      if (gen === searchGen) {
        searchResults = results || [];
      }
    } catch (err) {
      if (gen === searchGen) console.error(err);
    } finally {
      if (gen === searchGen) isSearching = false;
    }
  }

  function handleInput() {
    // If they start searching, exit theater AND watchlist to show results
    selectedAnime = null;
    currentView = "discovery";
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(performSearch, 500);
  }

  async function handleLogin() {
    if (isUserLoggedIn) {
      // Logout Flow
      if (confirm("Are you sure you want to log out of AniList?")) {
        await Logout();
        isUserLoggedIn = false;
        if (currentView === "watchlist") handleHome(); // Boot them out of watchlist if logged out
      }
    } else {
      // Login Flow
      try {
        const result = await LoginWithAniList();
        if (result === "success") {
          isUserLoggedIn = true;
        }
      } catch (err) {
        console.error("OAuth2 Failed:", err);
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
    onWatchlist={() => {
      selectedAnime = null;
      currentView = "watchlist";
    }}
  />

  {#if selectedAnime}
    <TheaterView anime={selectedAnime} onBack={() => (selectedAnime = null)} />
  {:else if currentView === "watchlist"}
    <Watchlist onSelectAnime={(anime) => (selectedAnime = anime)} />
  {:else}
    <DiscoveryView
      {searchQuery}
      {isSearching}
      {searchResults}
      onSelect={(anime) => (selectedAnime = anime)}
    />
  {/if}

  {#if isSettingsOpen}
    <SettingsMenu onClose={() => (isSettingsOpen = false)} />
  {/if}
</main>
