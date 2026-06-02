<script lang="ts">
    import { createEventDispatcher } from "svelte";
    import {
        ArrowLeft,
        Play,
        CloudDownload,
        LoaderCircle,
    } from "lucide-svelte";
    import type { main } from "../../wailsjs/go/models";
    import { GetEpisodeMagnet, StreamTorrent } from "../../wailsjs/go/main/App";

    export let anime: main.Anime;

    const dispatch = createEventDispatcher();

    let isScraping = false;
    let loadingEpisode = 0;
    let playingEpisode = 0;

    // New State Variable for the Video Player
    let streamUrl: string | null = null;

    function goBack() {
        // If they leave the theater, stop the video and go back to discovery
        streamUrl = null;
        playingEpisode = 0;
        dispatch("back");
    }

    $: episodeList = Array.from(
        { length: anime.episodes || 12 },
        (_, i) => i + 1,
    );

    async function playEpisode(epNum: number) {
        const titleToSearch = anime.title?.romaji || anime.title?.english || "";
        if (!titleToSearch) return;

        isScraping = true;
        loadingEpisode = epNum;
        streamUrl = null; // Reset the player if a new episode is clicked

        try {
            // 1. Scrape Nyaa for the magnet link
            console.log(`Scraping Nyaa for Episode ${epNum}...`);
            const torrent = await GetEpisodeMagnet(titleToSearch, epNum);

            // 2. Send the magnet link to the Go Engine
            console.log("Found Magnet! Booting torrent engine...");
            const url = await StreamTorrent(torrent.magnetLink);

            // 3. Mount the video player
            playingEpisode = epNum;
            streamUrl = url;
            console.log("Streaming from:", streamUrl);
        } catch (err) {
            console.log(err);
            alert(
                `Could not stream Episode ${epNum}. Check console for details.\n` +
                    err,
            );
        } finally {
            isScraping = false;
            loadingEpisode = 0;
        }
    }
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
                    >
                        {anime.status}
                    </span>
                    <span>{anime.episodes || "?"} Episodes</span>
                </div>
                <div
                    class="text-slate-400 text-sm leading-relaxed line-clamp-6 text-justify"
                >
                    {@html anime.description || "No synopsis available."}
                </div>
            </div>
        </div>

        <div class="w-full md:w-2/3 lg:w-3/4 flex flex-col">
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
                            &larr; Back to Episodes
                        </button>
                    </div>

                    <div
                        class="w-full bg-black rounded-xl overflow-hidden shadow-2xl border border-slate-800 aspect-video animate-in fade-in zoom-in-95"
                    >
                        <video
                            src={streamUrl}
                            controls
                            autoplay
                            class="w-full h-full"
                        >
                            <track
                                kind="captions"
                                srclang="en"
                                label="English"
                            />
                        </video>
                    </div>
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
                                >
                                    {epNum}
                                </span>
                                <span
                                    class="font-medium text-slate-300 group-hover:text-white transition-colors"
                                >
                                    Episode {epNum}
                                </span>
                            </div>

                            <button
                                on:click={() => playEpisode(epNum)}
                                disabled={isScraping &&
                                    loadingEpisode === epNum}
                                class="flex items-center space-x-2 bg-indigo-600 hover:bg-indigo-500 disabled:bg-indigo-800 disabled:cursor-not-allowed text-white px-4 py-2 rounded-lg font-medium transition-colors opacity-0 group-hover:opacity-100 scale-95 group-hover:scale-100"
                            >
                                {#if isScraping && loadingEpisode === epNum}
                                    <LoaderCircle
                                        size={18}
                                        class="animate-spin"
                                    />
                                    <span>Connecting...</span>
                                {:else}
                                    <CloudDownload size={18} />
                                    <span>Stream</span>
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
    /* Clean custom scrollbar for the episode list */
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
