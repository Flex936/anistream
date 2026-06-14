<script lang="ts">
  import type { anilist } from "$wails/go/models";
  import { formatStatus, getSidebarBadgeStyle } from "$lib/utils/statusColor";

  let { anime }: { anime: anilist.Anime } = $props();

  // Strip block-level tags while keeping inline formatting safe for AniList HTML
  function sanitize(html: string): string {
    if (!html) return "";
    // Safely removes HTML tags EXCEPT for br, i, b, em, strong
    const regex = /<(?!(\/?(br|i|b|em|strong))\b)[^>]+>/gi;
    return html.replace(regex, "");
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

    <div class="flex items-center space-x-3 text-sm text-muted font-medium">
      <span
        class="px-2 py-1 rounded border {getSidebarBadgeStyle(anime.status)}"
      >
        {formatStatus(anime.status)}
      </span>
      <span
        >{anime.episodes || anime.nextAiringEpisode.episode - 1 || "?"} Episodes</span
      >
    </div>

    <div class="text-muted text-sm leading-relaxed line-clamp-6 text-justify">
      {@html sanitize(anime.description || "No synopsis available.")}
    </div>
  </div>
</div>
