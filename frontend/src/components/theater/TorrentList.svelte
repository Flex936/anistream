<script lang="ts">
    import { createEventDispatcher } from "svelte";
    import {
        CloudDownload,
        Search,
        Star,
        HardDrive,
        Play,
        LoaderCircle,
    } from "lucide-svelte";
    import type { main } from "../../../wailsjs/go/models";

    export let fetchedTorrents: main.TorrentResult[];
    export let loadingEpisode: number;
    export let isStartingStream: boolean;

    const dispatch = createEventDispatcher();

    // Internal state - the parent doesn't need to track this
    let torrentSearch = "";

    $: filteredTorrents = fetchedTorrents.filter((t) =>
        t.title.toLowerCase().includes(torrentSearch.toLowerCase()),
    );
</script>

<div class="flex items-center justify-between mb-4">
    <h3 class="text-xl font-semibold text-slate-200 flex items-center">
        <CloudDownload size={20} class="mr-2 text-indigo-400" />
        Select Release for Episode {loadingEpisode}
    </h3>
    <button
        on:click={() => dispatch("back")}
        class="text-sm text-slate-400 hover:text-white transition-colors"
    >
        &larr; Episodes
    </button>
</div>

<div class="relative mb-4 group">
    <div
        class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-slate-500 group-focus-within:text-indigo-400"
    >
        <Search size={18} />
    </div>
    <input
        type="text"
        bind:value={torrentSearch}
        placeholder="Filter release groups (e.g., SubsPlease, 1080p)..."
        class="w-full bg-slate-900/50 border border-slate-700 text-slate-200 text-sm rounded-lg focus:ring-1 focus:ring-indigo-500 block pl-10 p-3 outline-none transition-colors"
    />
</div>

<div
    class="bg-slate-900 border border-slate-800 rounded-xl overflow-hidden flex-1 max-h-[550px] overflow-y-auto custom-scrollbar"
>
    {#each filteredTorrents as torrent, index}
        <div
            class="flex items-center justify-between p-4 border-b border-slate-800/50 transition-colors hover:bg-slate-800/80 {index ===
                0 && !torrentSearch
                ? 'bg-indigo-950/30 border-l-4 border-l-indigo-500'
                : ''}"
        >
            <div class="flex flex-col pr-4">
                <div class="flex items-center space-x-2">
                    {#if index === 0 && !torrentSearch}
                        <Star size={16} class="text-amber-400 fill-amber-400" />
                        <span
                            class="text-xs font-bold text-amber-400 uppercase tracking-wider"
                            >Recommended</span
                        >
                    {/if}
                </div>
                <span
                    class="font-medium text-sm text-slate-200 mt-1 line-clamp-2 leading-snug"
                    >{torrent.title}</span
                >
                <div
                    class="flex items-center space-x-4 mt-2 text-xs font-mono text-slate-500"
                >
                    <span class="flex items-center"
                        ><HardDrive size={12} class="mr-1" />
                        {torrent.size}</span
                    >
                    <span class="text-green-400/80"
                        >▲ {torrent.seeders} Seeders</span
                    >
                    <span>Score: {torrent.score}</span>
                </div>
            </div>

            <button
                on:click={() => dispatch("play", torrent.magnetLink)}
                disabled={isStartingStream}
                class="shrink-0 flex items-center space-x-2 bg-indigo-600 hover:bg-indigo-500 disabled:bg-indigo-800 disabled:cursor-not-allowed text-white px-4 py-2 rounded-lg font-medium transition-colors"
            >
                {#if isStartingStream}
                    <LoaderCircle size={18} class="animate-spin" />
                {:else}
                    <Play size={18} />
                {/if}
            </button>
        </div>
    {/each}
    {#if filteredTorrents.length === 0}
        <div class="p-8 text-center text-slate-500">
            No releases match your filter.
        </div>
    {/if}
</div>

<style>
    .custom-scrollbar::-webkit-scrollbar {
        width: 8px;
    }
    .custom-scrollbar::-webkit-scrollbar-track {
        background: transparent;
    }
    .custom-scrollbar::-webkit-scrollbar-thumb {
        background: #334155;
        border-radius: 4px;
    }
    .custom-scrollbar::-webkit-scrollbar-thumb:hover {
        background: #475569;
    }
</style>
