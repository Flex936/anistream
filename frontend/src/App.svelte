<script lang="ts">
  import { onMount } from "svelte";
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

  onMount(async () => {
    await loadHomePage();
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

  async function performSearch() {
    if (searchQuery.length == 0) {
      searchResults = await GetTrendingAnime();
      return;
    }
    isSearching = true;
    try {
      const results = await SearchAnime(searchQuery);
      searchResults = results || [];
    } catch (err) {
      console.error(err);
    } finally {
      isSearching = false;
    }
  }

  function handleInput() {
    // If they start searching, exit the theater view
    selectedAnime = null;
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(performSearch, 500);
  }
</script>

<main class="min-h-screen flex flex-col bg-slate-950">
  <NavBar bind:searchQuery on:search={handleInput} />

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
