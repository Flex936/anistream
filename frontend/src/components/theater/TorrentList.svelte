<script lang="ts">
    import { createEventDispatcher } from "svelte";
    import {
        Search,
        ArrowLeft,
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
    <h3 class="text-xl font-semibold text-main flex items-center">
        Select Release for Episode {loadingEpisode}
    </h3>
    <button
        on:click={() => dispatch("back")}
        class="flex items-center space-x-2 text-sm text-muted hover:text-main transition-colors"
    >
        <ArrowLeft size={16} />
        <span>Back to Release List</span>
    </button>
</div>

<div class="relative mb-4 group">
    <div
        class="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-muted group-focus-within:text-primary transition-colors"
    >
        <Search size={18} />
    </div>
    <input
        type="text"
        bind:value={torrentSearch}
        placeholder="Filter release groups (e.g., SubsPlease, 1080p)..."
        class="w-full bg-surface border border-border text-main text-sm rounded-lg focus:ring-1 focus:ring-primary block pl-10 p-3 outline-none transition-colors"
    />
</div>

<div
    class="bg-surface border border-border rounded-xl flex-1 max-h-[550px] overflow-y-auto p-2 space-y-1 custom-scrollbar"
>
    {#each filteredTorrents as torrent, index}
        <div
            class="group flex items-center justify-between p-3 rounded-lg transition-colors hover:bg-white/5 border {index ===
                0 && !torrentSearch
                ? 'bg-primary/10 border-primary/30'
                : 'border-transparent'}"
        >
            <div class="flex flex-col pr-4">
                <div class="flex items-center space-x-2">
                    {#if index === 0 && !torrentSearch}
                        <span
                            class="text-xs font-bold text-accent uppercase tracking-wider"
                            >Recommended</span
                        >
                    {/if}
                </div>

                <button
                    on:click={() => dispatch("play", torrent.magnetLink)}
                    disabled={isStartingStream}
                    class="text-left font-medium text-sm text-main mt-1 line-clamp-2 leading-snug group-hover:text-white hover:!text-primary transition-colors disabled:cursor-not-allowed focus:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded"
                >
                    {torrent.title}
                </button>

                <div
                    class="flex items-center space-x-4 mt-2 text-xs font-mono text-muted"
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
                class="shrink-0 flex items-center justify-center w-10 h-10 rounded-full transition-all duration-200
                    {isStartingStream
                    ? 'bg-primary/20 text-primary'
                    : 'bg-transparent text-muted/30 group-hover:bg-primary/10 group-hover:text-primary hover:!bg-primary hover:!text-white'} disabled:cursor-not-allowed"
            >
                {#if isStartingStream}
                    <LoaderCircle size={18} class="animate-spin" />
                {:else}
                    <Play size={18} class="ml-0.5" />
                {/if}
            </button>
        </div>
    {/each}
    {#if filteredTorrents.length === 0}
        <div class="p-8 text-center text-muted">
            No releases match your filter.
        </div>
    {/if}
</div>
