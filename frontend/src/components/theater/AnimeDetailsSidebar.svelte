<script lang="ts">
  import type { main } from "../../../wailsjs/go/models";
  import { formatStatus, getSidebarBadgeStyle } from "../../utils/statusColor";

  export let anime: main.Anime;

  $: availableEpisodes = (() => {
    if (anime.status === "RELEASING" && anime.nextAiringEpisode) {
      return anime.nextAiringEpisode.episode - 1;
    }
    return anime.episodes || 0;
  })();

  // Naive but effective for AniList's known output
  function sanitize(html: string) {
    return html.replace(/<(?!\/?(br|i|b|em|strong)\b)[^>]+>/gi, "");
  }
</script>

<div class="w-full md:w-1/3 lg:w-1/4 shrink-0">
  <img
    src={anime.coverImage?.large}
    alt="Cover"
    class="w-full rounded-xl shadow-2xl border border-border"
  />

  <div class="mt-6 space-y-4">
    <h2 class="text-2xl font-bold text-main leading-tight">
      {anime.title?.romaji || anime.title?.english}
    </h2>

    {#if anime.status === "RELEASING" && anime.nextAiringEpisode}
      <span class="text-xs font-semibold text-primary mt-1">
        {availableEpisodes} / {anime.episodes || "?"} Aired
      </span>
    {:else}
      <span class="text-xs text-muted mt-1"
        >{anime.episodes || "?"} Episodes</span
      >
    {/if}

    <div class="flex items-center space-x-3 text-sm text-muted font-medium">
      <span
        class="px-2 py-1 rounded border {getSidebarBadgeStyle(anime.status)}"
      >
        {formatStatus(anime.status)}
      </span>
      <span>{anime.episodes || "?"} Episodes</span>
    </div>

    <div class="text-muted text-sm leading-relaxed line-clamp-6 text-justify">
      {@html sanitize(anime.description || "No synopsis available.")}
    </div>
  </div>
</div>
