<script lang="ts">
  import { ArrowLeft } from "@lucide/svelte";
  import type { main } from "../../wailsjs/go/models";
  import {
    GetEpisodeTorrents,
    StreamTorrent,
    StopStream,
  } from "../../wailsjs/go/main/App";

  import AnimeDetailsSidebar from "../components/theater/AnimeDetailsSidebar.svelte";
  import EpisodeList from "../components/theater/EpisodeList.svelte";
  import TorrentList from "../components/theater/TorrentList.svelte";
  import VideoPlayer from "../components/theater/VideoPlayer.svelte";

  let {
    anime,
    onBack,
  }: {
    anime: main.Anime;
    onBack: () => void;
  } = $props();

  let isScraping = $state(false);
  let isStartingStream = $state(false);
  let loadingEpisode = $state(0);
  let playingEpisode = $state(0);
  let streamUrl = $state<string | null>(null);
  let fetchedTorrents = $state<main.TorrentResult[]>([]);

  let scrapingGen = 0;

  let availableEpisodes = $derived.by(() => {
    if (anime.status === "RELEASING" && anime.nextAiringEpisode) {
      return anime.nextAiringEpisode.episode - 1;
    }
    return anime.episodes || 0;
  });

  let episodeList = $derived(
    anime.episodes
      ? Array.from({ length: anime.episodes }, (_, i) => i + 1)
      : [],
  );

  function goBack() {
    scrapingGen++; // Invalidate requests
    streamUrl = null;
    fetchedTorrents = [];
    playingEpisode = 0;
    loadingEpisode = 0;
    isScraping = false;

    onBack();

    // Ensure we kill the torrent if the user backs out
    StopStream().catch((err) =>
      console.error("Failed to cancel torrent load:", err),
    );
  }

  async function handleFetchTorrents(epNum: number) {
    const titleToSearch = anime.title?.romaji || anime.title?.english || "";
    if (!titleToSearch) return;

    const gen = ++scrapingGen;
    isScraping = true;
    loadingEpisode = epNum;
    fetchedTorrents = [];

    try {
      const results = await GetEpisodeTorrents(titleToSearch, epNum);
      if (gen === scrapingGen) fetchedTorrents = results || [];
    } catch (err) {
      if (gen === scrapingGen) alert(`Error: ${err}`);
    } finally {
      if (gen === scrapingGen) isScraping = false;
    }
  }

  // Magnet link passed directly instead of CustomEvent
  async function handleStartStream(magnet: string) {
    isStartingStream = true;
    try {
      const url = await StreamTorrent(magnet);
      playingEpisode = loadingEpisode;
      streamUrl = url;
    } catch (err) {
      alert(`Failed to connect to peers.\n${err}`);
    } finally {
      isStartingStream = false;
    }
  }
</script>

<div
  class="flex-1 p-8 max-w-7xl mx-auto w-full animate-in fade-in slide-in-from-bottom-4 duration-500"
>
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
      {#if streamUrl}
        <VideoPlayer
          {streamUrl}
          {playingEpisode}
          animeId={anime.id}
          onBack={() => {
            streamUrl = null;
            playingEpisode = 0;
          }}
        />
      {:else if fetchedTorrents.length > 0}
        <TorrentList
          {fetchedTorrents}
          {loadingEpisode}
          {isStartingStream}
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
