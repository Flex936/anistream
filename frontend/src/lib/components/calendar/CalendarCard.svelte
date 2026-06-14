<script lang="ts">
    import { anilist } from "$wails/go/models";

    let {
        anime,
        formatLocalTime,
        getTimeRemaining,
    }: {
        anime: anilist.Anime;
        formatLocalTime: (arg0: number) => string;
        getTimeRemaining: (arg0: number) => string;
    } = $props();
    let isLoaded = $state(false);
</script>

<!-- Cover image -->
<div
    class="relative aspect-2/3 w-full rounded-xl overflow-hidden shadow-lg border border-border mb-2
            group-hover:border-primary/50 transition-colors cursor-pointer"
>
    <img
        src={anime.coverImage.large}
        alt={anime.title.romaji || anime.title.english || "Anime Title"}
        class="w-full h-full object-cover transition-all duration-300 group-hover:scale-105
               {isLoaded ? 'opacity-100' : 'opacity-0'}"
        loading="lazy"
        onload={() => (isLoaded = true)}
    />

    <!-- Skeleton -->
    {#if !isLoaded}
        <div class="absolute inset-0 bg-surface animate-pulse"></div>
    {/if}

    <!-- Hover overlay -->
    <div
        class="absolute inset-0 bg-linear-to-t from-black/80 via-transparent to-transparent
                opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex items-end p-2"
    >
        <div
            class="bg-primary text-white px-2 py-0.5 rounded-full text-[10px] font-bold shadow-lg"
        >
            Ep {anime.nextAiringEpisode.episode > 0
                ? anime.nextAiringEpisode.episode
                : anime.episodes || "?"}
        </div>
    </div>

    <!-- Airing time badge (always visible) -->
    <div
        class="absolute top-2 right-2 bg-black/70 backdrop-blur-sm text-success
                px-1.5 py-0.5 rounded-md text-[10px] font-mono border border-success/30"
    >
        {formatLocalTime(anime.nextAiringEpisode.airingAt)}
    </div>
</div>

<!-- Title + countdown -->
<h3
    class="text-xs font-bold text-main line-clamp-1 group-hover:text-primary transition-colors"
    title={anime.title.romaji || anime.title.english}
>
    {anime.title.romaji || anime.title.english}
</h3>
<p class="text-[10px] text-muted mt-0.5 font-mono">
    {getTimeRemaining(anime.nextAiringEpisode.airingAt)}
</p>
