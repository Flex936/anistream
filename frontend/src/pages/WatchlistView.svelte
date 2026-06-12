<script lang="ts">
  import { onMount } from "svelte";
  import { GetUserWatchlist } from "$wails/go/main/App";
  import type { anilist } from "$wails/go/models";
  import { Play, Calendar, LoaderCircle } from "@lucide/svelte";

  let { onSelectAnime }: { onSelectAnime?: (anime: anilist.Anime) => void } =
    $props();

  let watchlists = $state<anilist.MediaList[]>([]);
  let isLoading = $state(true);
  let activeTab = $state<"CURRENT" | "PLANNING">("CURRENT");

  onMount(async () => {
    try {
      watchlists = await GetUserWatchlist();
    } catch (err) {
      console.error("Failed to load watchlist:", err);
    } finally {
      isLoading = false;
    }
  });

  let activeList = $derived(
    watchlists.find((list) => list.status === activeTab)?.entries || [],
  );
</script>

<div class="w-full max-w-6xl mx-auto p-8 animate-in fade-in duration-300">
  <div class="flex items-center justify-between mb-8">
    <h1 class="text-3xl font-bold text-main">My Library</h1>

    <div class="flex bg-surface p-1 rounded-xl border border-border">
      <button
        class="flex items-center space-x-2 px-6 py-2 rounded-lg text-sm font-semibold transition-all
               {activeTab === 'CURRENT'
          ? 'bg-primary text-white shadow-md'
          : 'text-muted hover:text-main'}"
        onclick={() => (activeTab = "CURRENT")}
      >
        <Play size={16} /><span>Watching</span>
      </button>
      <button
        class="flex items-center space-x-2 px-6 py-2 rounded-lg text-sm font-semibold transition-all
               {activeTab === 'PLANNING'
          ? 'bg-primary text-white shadow-md'
          : 'text-muted hover:text-main'}"
        onclick={() => (activeTab = "PLANNING")}
      >
        <Calendar size={16} /><span>Planning</span>
      </button>
    </div>
  </div>

  {#if isLoading}
    <div class="flex justify-center items-center h-64">
      <LoaderCircle size={32} class="animate-spin text-primary" />
    </div>
  {:else if activeList.length === 0}
    <div
      class="flex flex-col items-center justify-center h-64 text-muted bg-surface rounded-xl border border-border border-dashed"
    >
      <p class="text-lg font-medium">Your list is empty.</p>
      <p class="text-sm">Find something new to watch!</p>
    </div>
  {:else}
    <div
      class="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-5 gap-6"
    >
      {#each activeList as entry}
        <button
          class="group text-left focus:outline-none"
          onclick={() => onSelectAnime?.(entry.media)}
        >
          <div
            class="relative aspect-2/3 w-full rounded-xl overflow-hidden shadow-lg border border-border mb-3"
          >
            <img
              src={entry.media.coverImage.large}
              alt={entry.media.title.english || entry.media.title.romaji}
              class="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
            />

            <div
              class="absolute inset-0 bg-linear-to-t from-black/80 via-transparent to-transparent
                     opacity-0 group-hover:opacity-100 transition-opacity duration-300
                     flex items-end p-4"
            >
              <div
                class="bg-primary text-white px-3 py-1 rounded-full text-xs font-bold shadow-lg"
              >
                Play EP {entry.progress + 1}
              </div>
            </div>

            {#if activeTab === "CURRENT"}
              <div
                class="absolute top-2 right-2 bg-black/80 backdrop-blur-sm text-white px-2 py-1 rounded-md text-xs font-bold border border-white/10"
              >
                {entry.progress} / {entry.media.episodes || "?"}
              </div>
            {/if}
          </div>

          <h3
            class="text-sm font-bold text-main line-clamp-1 group-hover:text-primary transition-colors"
          >
            {entry.media.title.english || entry.media.title.romaji}
          </h3>
          {#if entry.media.nextAiringEpisode}
            <p class="text-xs text-primary font-semibold mt-1">
              Ep {entry.media.nextAiringEpisode.episode} airing soon
            </p>
          {/if}
        </button>
      {/each}
    </div>
  {/if}
</div>
