<script lang="ts">
  import { CirclePlay } from "@lucide/svelte";
  import { formatStatus, getCardStatusColor } from "$lib/utils/statusColor";

  let { anime, onSelect } = $props();

  let isLoaded = $state(false);

  function selectAnime() {
    onSelect?.(anime);
  }
</script>

<button
  class="group relative flex flex-col cursor-pointer text-left w-full focus:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded-xl"
  onclick={selectAnime}
>
  <div
    class="relative w-full aspect-2/3 rounded-xl overflow-hidden shadow-lg border border-border
           bg-surface group-hover:border-primary/50 transition-colors"
  >
    <!-- Skeleton shimmer -->
    <div
      class="absolute inset-0 bg-surface animate-pulse {isLoaded
        ? 'hidden'
        : 'block'}"
    ></div>

    <img
      src={anime.coverImage?.large || ""}
      alt={anime.title?.romaji || anime.title?.english || "Anime Cover"}
      class="w-full h-full object-cover transition-opacity duration-500 {isLoaded
        ? 'opacity-100'
        : 'opacity-0'}"
      loading="lazy"
      onload={() => (isLoaded = true)}
    />

    <!-- Status badge -->
    <div
      class="absolute top-2 left-2 bg-black/70 backdrop-blur-sm px-2 py-1 rounded text-xs
             font-semibold border shadow-md transition-colors {getCardStatusColor(
        anime.status,
      )}"
    >
      {formatStatus(anime.status)}
    </div>

    <!-- Hover overlay -->
    <div
      class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100
             flex items-center justify-center transition-opacity"
    >
      <div
        class="bg-primary rounded-full shadow-xl transform translate-y-4
               group-hover:translate-y-0 transition-transform"
      >
        <CirclePlay size={48} strokeWidth={1.5} />
      </div>
    </div>
  </div>

  <div class="mt-3 flex flex-col">
    <h3
      class="font-medium text-sm text-main line-clamp-2 leading-snug
             group-hover:text-primary transition-colors"
    >
      {anime.title?.romaji || anime.title?.english || "Unknown Title"}
    </h3>
    <span class="text-xs text-muted mt-1"
      >{anime.episodes || anime.nextAiringEpisode.episode - 1 || "?"} Episodes</span
    >
  </div>
</button>
