<script lang="ts">
    import type { main } from "../../../wailsjs/go/models";

    export let anime: main.Anime;

    // Naive but effective for AniList's known output
    function sanitize(html: string) {
        return html.replace(/<(?!\/?(br|i|b|em|strong)\b)[^>]+>/gi, "");
    }
</script>

<div class="w-full md:w-1/3 lg:w-1/4 shrink-0">
    <img
        src={anime.coverImage?.large}
        alt="Cover"
        class="w-full rounded-xl shadow-2xl border border-slate-800"
    />
    <div class="mt-6 space-y-4">
        <h2 class="text-2xl font-bold text-white leading-tight">
            {anime.title?.romaji || anime.title?.english}
        </h2>
        <div
            class="flex items-center space-x-3 text-sm text-slate-300 font-medium"
        >
            <span
                class="bg-indigo-500/20 text-indigo-300 px-2 py-1 rounded border border-indigo-500/30"
            >
                {anime.status}
            </span>
            <span>{anime.episodes || "?"} Episodes</span>
        </div>
        <div
            class="text-slate-400 text-sm leading-relaxed line-clamp-6 text-justify"
        >
            {@html sanitize(anime.description || "No synopsis available.")}
        </div>
    </div>
</div>
