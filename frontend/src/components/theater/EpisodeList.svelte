<script lang="ts">
    import { createEventDispatcher } from "svelte";
    import { Search, LoaderCircle } from "lucide-svelte";

    export let episodeList: number[];
    export let isScraping: boolean;
    export let loadingEpisode: number;

    const dispatch = createEventDispatcher();
</script>

<h3 class="text-xl font-semibold text-slate-200 mb-4 flex items-center">
    Select Episode
</h3>
<div
    class="bg-slate-900 border border-slate-800 rounded-xl overflow-hidden flex-1 max-h-[600px] overflow-y-auto custom-scrollbar"
>
    {#each episodeList as epNum}
        <div
            class="flex items-center justify-between p-4 border-b border-slate-800/50 hover:bg-slate-800/80 transition-colors group"
        >
            <div class="flex items-center space-x-4">
                <span
                    class="text-2xl font-bold text-slate-700 group-hover:text-slate-500 transition-colors w-8"
                    >{epNum}</span
                >
                <span
                    class="font-medium text-slate-300 group-hover:text-white transition-colors"
                    >Episode {epNum}</span
                >
            </div>
            <button
                on:click={() => dispatch("select", epNum)}
                disabled={isScraping}
                class="flex items-center space-x-2 bg-slate-800 hover:bg-slate-700 text-slate-300 px-4 py-2 rounded-lg font-medium transition-colors"
            >
                {#if isScraping && loadingEpisode === epNum}
                    <LoaderCircle
                        size={18}
                        class="animate-spin text-indigo-400"
                    />
                    <span>Searching...</span>
                {:else}
                    <Search size={18} />
                    <span>Find Releases</span>
                {/if}
            </button>
        </div>
    {/each}
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
