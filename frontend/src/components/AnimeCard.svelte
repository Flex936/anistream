<script lang="ts">
    import { createEventDispatcher } from "svelte";
    import { CirclePlay } from "lucide-svelte";
    import type { main } from "../../wailsjs/go/models";

    export let anime: main.Anime;

    const dispatch = createEventDispatcher();

    function selectAnime() {
        dispatch("select", anime);
    }
</script>

<article
    class="group relative flex flex-col cursor-pointer ..."
    on:click={selectAnime}
    on:keydown={(e) => (e.key === "Enter" || e.key === " ") && selectAnime()}
>
    <div
        class="relative w-full aspect-[2/3] rounded-xl overflow-hidden shadow-lg border border-slate-800 bg-slate-900 group-hover:border-indigo-500/50 transition-colors"
    >
        <img
            src={anime.coverImage?.large || ""}
            alt={anime.title?.romaji || anime.title?.english || "Anime Cover"}
            class="w-full h-full object-cover"
            loading="lazy"
        />

        <div
            class="absolute top-2 left-2 bg-black/70 backdrop-blur-sm px-2 py-1 rounded text-xs font-semibold text-white border shadow-md
        {anime.status === 'RELEASING'
                ? 'text-green-400 border-green-400/20'
                : 'text-slate-300 border-slate-500/20'}"
        >
            {anime.status || "UNKNOWN"}
        </div>

        <div
            class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity"
        >
            <div
                class="bg-indigo-600 rounded-full shadow-xl transform translate-y-4 group-hover:translate-y-0 transition-transform"
            >
                <CirclePlay
                    size={48}
                    class="text-white fill-indigo-600"
                    strokeWidth={1.5}
                />
            </div>
        </div>
    </div>

    <div class="mt-3 flex flex-col">
        <h3
            class="font-medium text-sm text-slate-200 line-clamp-2 leading-snug group-hover:text-indigo-400 transition-colors"
        >
            {anime.title?.romaji || anime.title?.english || "Unknown Title"}
        </h3>
        <span class="text-xs text-slate-500 mt-1"
            >{anime.episodes || "?"} Episodes</span
        >
    </div>
</article>
