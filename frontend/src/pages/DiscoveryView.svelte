<script lang="ts">
  import AnimeCard from "$lib/components/ui/AnimeCard.svelte";
  import { LoaderCircle } from "@lucide/svelte";
  import type { anilist } from "$wails/go/models";

  let {
    searchQuery,
    isSearching,
    searchResults,
    onSelect,
  }: {
    searchQuery: string;
    isSearching: boolean;
    searchResults: anilist.Anime[];
    onSelect: (anime: anilist.Anime) => void;
  } = $props();
</script>

<div class="flex-1 p-8 max-w-7xl mx-auto w-full">
  <div class="mb-8 flex items-center justify-between">
    <h2 class="text-2xl font-semibold text-main">
      {#if searchQuery}Results for "{searchQuery}"{:else}Discover{/if}
    </h2>
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
