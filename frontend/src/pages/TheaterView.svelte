<script lang="ts">
  import { onDestroy } from "svelte";
  import { ArrowLeft } from "@lucide/svelte";
  import type { anilist, scraper } from "$wails/go/models";
  import {
    GetEpisodeTorrents,
    StreamTorrent,
    StopStream,
  } from "$wails/go/main/App";

  import AnimeDetailsSidebar from "$lib/components/theater/AnimeDetailsSidebar.svelte";
  import EpisodeList from "$lib/components/theater/EpisodeList.svelte";
  import TorrentList from "$lib/components/theater/TorrentList.svelte";
  import VideoPlayer from "$lib/components/theater/VideoPlayer.svelte";

  let {
    anime,
    onBack,
    isLoggedIn = false,
  }: {
    anime: anilist.Anime;
    onBack: () => void;
    isLoggedIn?: boolean;
  } = $props();

  let isScraping = $state(false);
  let isStartingStream = $state(false);
  let loadingEpisode = $state(0);
  let playingEpisode = $state(0);

  // ── Stream state ────────────────────────────────────────────────────────────
  // Old architecture: streamUrl (string | null) — the HLS manifest URL returned
  //   by StreamTorrent was handed to hls.js which played it in a <video> element.
  //
  // New architecture: isStreaming (boolean) — StreamTorrent no longer returns a
  //   URL because there is no HLS manifest.  MPV plays the torrent natively via
  //   --wid.  When isStreaming = true, VideoPlayer mounts as a fixed full-screen
  //   transparent overlay; MPV's render layer shows through behind it.
  let isStreaming = $state(false);

  let fetchedTorrents = $state<scraper.TorrentResult[]>([]);
  let scrapingGen = 0;

  let availableEpisodes = $derived.by(() => {
    if (anime.status === "RELEASING" && anime.nextAiringEpisode) {
      return anime.nextAiringEpisode.episode - 1;
    }
    return anime.episodes || 0;
  });

  // ── Navigation ─────────────────────────────────────────────────────────────
  function goBack(): void {
    scrapingGen++;
    onBack();
  }

  // ── Torrent scraping ────────────────────────────────────────────────────────
  async function handleFetchTorrents(epNum: number): Promise<void> {
    const title = anime.title?.romaji || anime.title?.english || "";
    if (!title) return;

    const gen = ++scrapingGen;
    isScraping = true;
    loadingEpisode = epNum;
    fetchedTorrents = [];

    try {
      const results = await GetEpisodeTorrents(title, epNum);
      if (gen === scrapingGen) fetchedTorrents = results || [];
    } catch (err) {
      if (gen === scrapingGen) alert(`Error fetching torrents: ${err}`);
    } finally {
      if (gen === scrapingGen) isScraping = false;
    }
  }

  // ── Stream start ────────────────────────────────────────────────────────────
  async function handleStartStream(magnet: string): Promise<void> {
    // Instantly trigger the UI state change
    isStartingStream = true;
    playingEpisode = loadingEpisode;
    isStreaming = true;

    try {
      await StreamTorrent(magnet);
    } catch (err) {
      alert(`Failed to start stream.\n${err}`);
      isStreaming = false;
    } finally {
      isStartingStream = false;
    }
  }

  // ── Stream stop — called by VideoPlayer's back button ──────────────────────
  async function handleStopStream(): Promise<void> {
    isStreaming = false; // unmounts VideoPlayer overlay first
    playingEpisode = 0;
    await StopStream().catch(console.warn);
    // Return to torrent list so the user can pick a different release.
  }

  // ── Cleanup on navigation away from TheaterView ────────────────────────────
  // This fires when the user navigates to Discovery or Watchlist while a stream
  // is active — VideoPlayer's own onDestroy does NOT call StopStream() so the
  // two paths don't race.
  onDestroy(() => {
    scrapingGen++;
    StopStream().catch(console.warn);
  });
</script>

<!--
  Theater layout:
    • Normal mode:  sidebar + episode/torrent list (standard flex layout).
    • Streaming:    VideoPlayer mounts as a fixed inset-0 z-[100] glass pane.
      The sidebar and lists remain mounted in the DOM but are fully covered by
      the transparent overlay; MPV's native video layer shows through behind it.
-->
<div
  class="flex-1 p-8 max-w-7xl mx-auto w-full animate-in fade-in slide-in-from-bottom-4 duration-500"
>
  <!-- Back to discovery -->
  <button
    onclick={goBack}
    class="flex items-center space-x-2 text-muted hover:text-main transition-colors mb-8 group"
  >
    <ArrowLeft
      size={20}
      class="group-hover:-translate-x-1 transition-transform"
    />
    <span>Back to Discovery</span>
  </button>

  <div class="flex flex-col md:flex-row gap-10">
    <AnimeDetailsSidebar {anime} />

    <div class="w-full md:w-2/3 lg:w-3/4 flex flex-col min-h-[500px]">
      {#if fetchedTorrents.length > 0}
        <TorrentList
          {fetchedTorrents}
          {loadingEpisode}
          onBack={() => {
            fetchedTorrents = [];
            loadingEpisode = 0;
          }}
          onPlay={handleStartStream}
        />
      {:else}
        <EpisodeList
          {availableEpisodes}
          {anime}
          {isScraping}
          {loadingEpisode}
          onSelect={handleFetchTorrents}
        />
      {/if}
    </div>
  </div>
</div>

<!--
  VideoPlayer is rendered OUTSIDE the content flex container so that its
  fixed positioning is relative to the viewport, not a positioned ancestor.
  It only mounts when isStreaming = true.
-->
{#if isStreaming}
  <VideoPlayer
    {playingEpisode}
    animeId={anime.id}
    {isLoggedIn}
    isLoading={isStartingStream}
    onBack={handleStopStream}
  />
{/if}
