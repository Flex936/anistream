<script lang="ts">
    import { createEventDispatcher, onDestroy } from "svelte";
    import {
        ArrowLeft,
        Play,
        CloudDownload,
        LoaderCircle,
        Search,
        Star,
        HardDrive,
    } from "lucide-svelte";
    import type { main } from "../../wailsjs/go/models";
    import {
        GetEpisodeTorrents,
        StreamTorrent,
    } from "../../wailsjs/go/main/App";

    export let anime: main.Anime;
    const dispatch = createEventDispatcher();

    // State Variables
    let isScraping = false;
    let isStartingStream = false;
    let loadingEpisode = 0;
    let playingEpisode = 0;

    let streamUrl: string | null = null;
    let fetchedTorrents: main.TorrentResult[] = [];
    let torrentSearch = "";

    // Canvas Frame Loop References
    let canvasRef: HTMLCanvasElement;
    let hiddenImg: HTMLImageElement | null = null;
    let animationFrameId: number;

    $: episodeList = Array.from(
        { length: anime.episodes || 12 },
        (_, i) => i + 1,
    );

    $: filteredTorrents = fetchedTorrents.filter((t) =>
        t.title.toLowerCase().includes(torrentSearch.toLowerCase()),
    );

    // Watcher: Automatically handle initialization/destruction of the canvas loop based on stream state
    $: if (streamUrl && canvasRef) {
        initCanvasLoop();
    } else {
        stopCanvasLoop();
    }

    function initCanvasLoop() {
        stopCanvasLoop();

        hiddenImg = new Image();
        hiddenImg.src = "http://localhost:8080/mpv-frame-stream";

        const ctx = canvasRef.getContext("2d");

        // Match explicit standard high-definition output limits
        canvasRef.width = 1920;
        canvasRef.height = 1080;

        function renderLoop() {
            if (!streamUrl || !canvasRef || !ctx || !hiddenImg) return;

            // Draw the current frame directly onto the canvas layout
            try {
                if (hiddenImg.width > 0 && hiddenImg.height > 0) {
                    ctx.drawImage(hiddenImg, 0, 0, canvasRef.width, canvasRef.height);
                }
            } catch (e) {
                // Ignore drawing exceptions during startup/transition phases
            }
            animationFrameId = requestAnimationFrame(renderLoop);
        }

        animationFrameId = requestAnimationFrame(renderLoop);
    }

    function stopCanvasLoop() {
        if (animationFrameId) {
            cancelAnimationFrame(animationFrameId);
        }
        if (hiddenImg) {
            hiddenImg.src = "";
            hiddenImg = null;
        }
    }

    function goBack() {
        streamUrl = null;
        fetchedTorrents = [];
        playingEpisode = 0;
        dispatch("back");
    }

    async function fetchTorrents(epNum: number) {
        const titleToSearch = anime.title?.romaji || anime.title?.english || "";
        if (!titleToSearch) return;

        isScraping = true;
        loadingEpisode = epNum;
        fetchedTorrents = [];
        torrentSearch = "";

        try {
            const results = await GetEpisodeTorrents(titleToSearch, epNum);
            fetchedTorrents = results;
        } catch (err) {
            console.error(err);
            alert(`Could not find torrents for Episode ${epNum}.\n${err}`);
        } finally {
            isScraping = false;
        }
    }

    async function startStream(magnet: string) {
        isStartingStream = true;
        try {
            const url = await StreamTorrent(magnet);
            playingEpisode = loadingEpisode;
            streamUrl = url;
        } catch (err) {
            console.error(err);
            alert(`Failed to connect to peers.\n${err}`);
        } finally {
            isStartingStream = false;
        }
    }

    onDestroy(() => {
        stopCanvasLoop();
    });
</script>

<div
    class="flex-1 p-8 max-w-7xl mx-auto w-full animate-in fade-in slide-in-from-bottom-4 duration-500"
>
    <button
        on:click={goBack}
        class="flex items-center space-x-2 text-slate-400 hover:text-white transition-colors mb-8 group"
    >
        <ArrowLeft
            size={20}
            class="group-hover:-translate-x-1 transition-transform"
        />
        <span>Back to Discovery</span>
    </button>

    <div class="flex flex-col md:flex-row gap-10">
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
                        >{anime.status}</span
                    >
                    <span>{anime.episodes || "?"} Episodes</span>
                </div>
                <div
                    class="text-slate-400 text-sm leading-relaxed line-clamp-6 text-justify"
                >
                    {@html anime.description || "No synopsis available."}
                </div>
            </div>
        </div>

        <div class="w-full md:w-2/3 lg:w-3/4 flex flex-col min-h-[500px]">
            {#if streamUrl}
                <div class="flex flex-col space-y-4 w-full">
                    <div class="flex items-center justify-between">
                        <h3
                            class="text-xl font-semibold text-slate-200 flex items-center"
                        >
                            <Play size={20} class="mr-2 text-indigo-400" />
                            Now Playing: Episode {playingEpisode}
                        </h3>
                        <button
                            on:click={() => {
                                streamUrl = null;
                                playingEpisode = 0;
                            }}
                            class="text-sm text-indigo-400 hover:text-indigo-300 transition-colors"
                        >
                            &larr; Back to Release List
                        </button>
                    </div>

                    <div
                        class="w-full bg-black rounded-xl overflow-hidden shadow-2xl border border-slate-800 aspect-video animate-in fade-in zoom-in-95"
                    >
                        <canvas
                            bind:this={canvasRef}
                            class="w-full h-full object-contain bg-slate-950"
                        ></canvas>
                    </div>
                </div>
            {:else if fetchedTorrents.length > 0}
                <div class="flex items-center justify-between mb-4">
                    <h3
                        class="text-xl font-semibold text-slate-200 flex items-center"
                    >
                        <CloudDownload size={20} class="mr-2 text-indigo-400" />
                        Select Release for Episode {loadingEpisode}
                    </h3>
                    <button
                        on:click={() => {
                            fetchedTorrents = [];
                            loadingEpisode = 0;
                        }}
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
                                        <Star
                                            size={16}
                                            class="text-amber-400 fill-amber-400"
                                        />
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
                                        ><HardDrive
                                            size={12}
                                            class="mr-1"
                                        />{torrent.size}</span
                                    >
                                    <span class="text-green-400/80"
                                        >▲ {torrent.seeders} Seeders</span
                                    >
                                    <span>Score: {torrent.score}</span>
                                </div>
                            </div>

                            <button
                                on:click={() => startStream(torrent.magnetLink)}
                                disabled={isStartingStream}
                                class="shrink-0 flex items-center space-x-2 bg-indigo-600 hover:bg-indigo-500 disabled:bg-indigo-800 disabled:cursor-not-allowed text-white px-4 py-2 rounded-lg font-medium transition-colors"
                            >
                                {#if isStartingStream}
                                    <LoaderCircle
                                        size={18}
                                        class="animate-spin"
                                    />
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
            {:else}
                <h3
                    class="text-xl font-semibold text-slate-200 mb-4 flex items-center"
                >
                    <Play size={20} class="mr-2 text-indigo-400" />
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
                                on:click={() => fetchTorrents(epNum)}
                                disabled={isScraping &&
                                    loadingEpisode === epNum}
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
            {/if}
        </div>
    </div>
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
