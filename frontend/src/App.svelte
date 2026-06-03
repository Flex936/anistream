<script lang="ts">
  import { SearchAnime } from "../wailsjs/go/main/App";
  import type { main } from "../wailsjs/go/models";

  import NavBar from "./components/NavBar.svelte";
  import DiscoveryView from "./pages/DiscoveryView.svelte";
  import TheaterView from "./pages/TheaterView.svelte";

  // State Variables
  let searchQuery = "";
  let isSearching = false;
  let searchResults: main.Anime[] = [];
  let searchTimeout: ReturnType<typeof setTimeout>;

  // Routing State
  let selectedAnime: main.Anime | null = null;

  async function performSearch() {
    if (searchQuery.trim().length < 3) {
      searchResults = [];
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
