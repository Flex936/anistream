<script lang="ts">
  import { createEventDispatcher } from "svelte";
  import { Search, LoaderCircle } from "lucide-svelte";
  import type { main } from "../../../wailsjs/go/models";

  export let episodeList: number[];
  export let availableEpisodes: number;
  export let anime: main.Anime;
  export let isScraping: boolean;
  export let loadingEpisode: number;

  const dispatch = createEventDispatcher();
</script>

<div class="flex items-center justify-between mb-4 border-b border-border pb-4">
  <h3 class="text-2xl font-bold text-main">Episodes</h3>

  {#if anime.status === "RELEASING" && anime.nextAiringEpisode}
    <div class="flex items-center space-x-3 text-sm">
      <span
        class="bg-primary/20 text-primary px-3 py-1 rounded-full font-bold shadow-sm"
      >
        {availableEpisodes} / {anime.episodes || "?"} Aired
      </span>
      <span
        class="text-muted font-medium bg-surface px-3 py-1 rounded-full border border-border"
      >
        Next: Ep {anime.nextAiringEpisode.episode}
      </span>
    </div>
  {:else if anime.episodes}
    <span class="text-muted font-medium">{anime.episodes} Episodes</span>
  {/if}
</div>

<div
  class="bg-surface border border-border rounded-xl flex-1 max-h-[600px] overflow-y-auto p-2 space-y-1 custom-scrollbar"
>
  {#each episodeList as epNum}
    <div
      class="flex items-center justify-between p-2 pl-4 rounded-lg hover:bg-white/5 transition-colors group"
    >
      <div class="flex items-center space-x-4">
        <span
          class="text-2xl font-black text-muted/30 group-hover:text-primary/70 transition-colors w-10 text-center"
        >
          {epNum}
        </span>
        <span
          class="font-medium text-muted group-hover:text-main transition-colors"
        >
          Episode {epNum}
        </span>
      </div>

      <button
        on:click={() => dispatch("select", epNum)}
        disabled={isScraping}
        class="flex items-center space-x-2 px-4 py-2 rounded-md font-medium transition-all duration-200
                    {isScraping && loadingEpisode === epNum
          ? 'bg-primary/20 text-primary'
          : 'bg-transparent text-muted/70 group-hover:bg-white/10 group-hover:text-main hover:!bg-primary hover:!text-white'}"
      >
        {#if isScraping && loadingEpisode === epNum}
          <LoaderCircle size={18} class="animate-spin text-primary" />
          <span>Searching...</span>
        {:else}
          <Search size={18} />
          <span>Find Releases</span>
        {/if}
      </button>
    </div>
  {/each}
</div>
