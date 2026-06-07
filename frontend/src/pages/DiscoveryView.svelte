<script lang="ts">
  import AnimeCard from "../components/AnimeCard.svelte";
  import { LoaderCircle } from "@lucide/svelte";
  import type { main } from "../../wailsjs/go/models";

  let {
    searchQuery,
    isSearching,
    searchResults,
    onSelect,
  }: {
    searchQuery: string;
    isSearching: boolean;
    searchResults: main.Anime[];
    onSelect: (anime: main.Anime) => void;
  } = $props();
</script>

<div class="flex-1 p-8 max-w-7xl mx-auto w-full">
  <div class="mb-8 flex items-center justify-between">
    <div>
      <h2 class="text-2xl font-semibold text-main">
        {#if searchQuery}
          Results for "{searchQuery}"
        {:else}
          Discover
        {/if}
      </h2>
    </div>

    {#if isSearching}
      <LoaderCircle class="w-6 h-6 text-primary animate-spin" />
    {/if}
  </div>

  <div
    class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-6"
  >
    {#each searchResults as anime (anime.id)}
      <AnimeCard {anime} onSelect={() => onSelect(anime)} />
    {/each}
  </div>
</div>
