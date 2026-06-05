<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { LoginWithAniList, IsLoggedIn, Logout } from "../wailsjs/go/main/App";
  import { SearchAnime, GetTrendingAnime } from "../wailsjs/go/main/App";
  import type { main } from "../wailsjs/go/models";

  import NavBar from "./components/NavBar.svelte";
  import DiscoveryView from "./pages/DiscoveryView.svelte";
  import TheaterView from "./pages/TheaterView.svelte";

  // State Variables
  let searchQuery = "";
  let isSearching = false;
  let searchResults: main.Anime[] = [];
  let searchTimeout: ReturnType<typeof setTimeout>;
  let searchGen = 0;
  let isUserLoggedIn = false;

  onMount(async () => {
    try {
      isUserLoggedIn = await IsLoggedIn();
    } catch (err) {
      console.error("Failed to check login status:", err);
    }
  });

  onMount(async () => {
    await loadHomePage();
  });

  // Clear the pending timeout so it doesn't fire after the app closes
  onDestroy(() => {
    clearTimeout(searchTimeout);
  });

  async function loadHomePage() {
    isSearching = true;
    try {
      searchResults = await GetTrendingAnime();
    } catch (error) {
      console.error("Failed to load trending anime:", error);
    } finally {
      isSearching = false;
    }
  }

  // Routing State
  let selectedAnime: main.Anime | null = null;

  function handleHome() {
    selectedAnime = null;
    searchQuery = "";
    clearTimeout(searchTimeout);
    loadHomePage();
  }

  async function performSearch() {
    if (searchQuery.length === 0) {
      searchResults = await GetTrendingAnime();
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
    // If they start searching, exit the theater view
    selectedAnime = null;
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(performSearch, 500);
  }

  async function handleLogin() {
    if (isUserLoggedIn) {
      // Logout Flow
      if (confirm("Are you sure you want to log out of AniList?")) {
        await Logout();
        isUserLoggedIn = false;
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

<main class="min-h-screen flex flex-col bg-base">
  <NavBar
    bind:searchQuery
    isLoggedIn={isUserLoggedIn}
    on:search={handleInput}
    on:home={handleHome}
    on:login={handleLogin}
  />

  {#if selectedAnime}
    <TheaterView anime={selectedAnime} on:back={() => (selectedAnime = null)} />
  {:else}
    <DiscoveryView
      {searchQuery}
      {isSearching}
      {searchResults}
      on:select={(e) => (selectedAnime = e.detail)}
    />
  {/if}
</main>
