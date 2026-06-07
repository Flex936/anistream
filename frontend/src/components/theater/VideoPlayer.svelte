<script lang="ts">
  import { createEventDispatcher, onMount, onDestroy } from "svelte";
  import {
    GetAnimeProgress,
    UpdateAnimeProgress,
    StopStream,
  } from "../../../wailsjs/go/main/App";
  import Hls from "hls.js";

  // Props
  export let streamUrl: string;
  export let playingEpisode: number;
  export let animeId: number;

  const dispatch = createEventDispatcher();

  // ==========================================
  // 1. AniList Tracking State (From HEAD)
  // ==========================================
  let currentProgress = 0;
  let hasScrobbled = false;
  let isTrackingTimerActive = false;
  let trackingTimeout: ReturnType<typeof setTimeout>;

  // Shared Video State
  let currentTime = 0;
  let duration = 0;

  // ==========================================
  // 2. Custom Player State (From mpv-player)
  // ==========================================
  let hlsInstance: Hls | undefined;
  let videoElement: HTMLVideoElement;
  let playerContainer: HTMLDivElement;

  let paused = true;
  let volume = 1;
  let isMuted = false;

  let videoMetadata = {
    duration: 0,
    audio_tracks: [],
    subtitles: [],
    chapters: [],
  };
  let metadataInterval: ReturnType<typeof setInterval>;

  // ==========================================
  // 3. AniList Tracking Logic
  // ==========================================
  $: if (animeId && playingEpisode) {
    resetTracker();
  }

  async function resetTracker() {
    hasScrobbled = false;
    isTrackingTimerActive = false;
    clearTimeout(trackingTimeout);
    try {
      currentProgress = await GetAnimeProgress(animeId);
      console.log(
        `AniList Progress: Ep ${currentProgress} | Currently Watching: Ep ${playingEpisode}`,
      );
    } catch (err) {
      console.error("Failed to fetch progress", err);
    }
  }

  $: if (duration > 0 && !hasScrobbled) {
    const percentage = currentTime / duration;
    if (percentage >= 0.9) {
      if (!isTrackingTimerActive && playingEpisode > currentProgress) {
        isTrackingTimerActive = true;
        trackingTimeout = setTimeout(async () => {
          if (currentTime / duration >= 0.9) {
            await triggerAniListUpdate();
          } else {
            isTrackingTimerActive = false;
          }
        }, 5000);
      }
    } else {
      if (isTrackingTimerActive) {
        clearTimeout(trackingTimeout);
        isTrackingTimerActive = false;
      }
    }
  }

  async function triggerAniListUpdate() {
    hasScrobbled = true;
    isTrackingTimerActive = false;
    try {
      await UpdateAnimeProgress(animeId, playingEpisode);
    } catch (err) {
      console.error("Failed to scrobble to AniList", err);
      hasScrobbled = false;
    }
  }

  function handleBack() {
    forceScrobbleIfEligible();
    dispatch("back");
  }

  function forceScrobbleIfEligible() {
    clearTimeout(trackingTimeout);
    if (!hasScrobbled && duration > 0 && playingEpisode > currentProgress) {
      if (currentTime / duration >= 0.9) {
        triggerAniListUpdate();
      }
    }
  }

  // ==========================================
  // 4. Custom Player Logic
  // ==========================================
  async function fetchMetadata() {
    try {
      const res = await fetch("http://localhost:8080/anime-data");
      if (!res.ok) return;

      const data = await res.json();
      if (data && data.duration > 0) {
        videoMetadata = data;
        clearInterval(metadataInterval);
        duration = data.duration;
      }
    } catch (err) {
      // Silently wait for MPV pipe to open
    }
  }

  function initPlayer() {
    if (!streamUrl || !videoElement) return;

    if (hlsInstance) hlsInstance.destroy();

    if (videoElement.canPlayType("application/vnd.apple.mpegurl")) {
      videoElement.src = streamUrl;
    } else if (Hls.isSupported()) {
      hlsInstance = new Hls({
        maxBufferLength: 10,
        liveSyncDurationCount: 3,
      });

      hlsInstance.loadSource(streamUrl);
      hlsInstance.attachMedia(videoElement);

      hlsInstance.on(Hls.Events.MANIFEST_PARSED, () => {
        videoElement.play().catch((err) => {
          console.log("Autoplay blocked:", err);
        });
      });

      hlsInstance.on(Hls.Events.ERROR, function (event, data) {
        if (data.fatal) {
          switch (data.type) {
            case Hls.ErrorTypes.NETWORK_ERROR:
              hlsInstance?.startLoad();
              break;
            case Hls.ErrorTypes.MEDIA_ERROR:
              hlsInstance?.recoverMediaError();
              break;
            default:
              initPlayer();
              break;
          }
        }
      });
    }
  }

  $: if (streamUrl && videoElement) {
    initPlayer();
  }

  function formatTime(timeInSeconds: number) {
    if (isNaN(timeInSeconds)) return "0:00";
    const minutes = Math.floor(timeInSeconds / 60);
    const seconds = Math.floor(timeInSeconds % 60);
    return `${minutes}:${seconds.toString().padStart(2, "0")}`;
  }

  function togglePlay() {
    paused = !paused;
  }
  function toggleMute() {
    isMuted = !isMuted;
  }
  function toggleFullscreen() {
    if (!document.fullscreenElement) {
      playerContainer.requestFullscreen().catch((err) => console.error(err));
    } else {
      document.exitFullscreen();
    }
  }

  // ==========================================
  // 5. Unified Lifecycles
  // ==========================================
  onMount(() => {
    metadataInterval = setInterval(fetchMetadata, 1000);
  });

  onDestroy(() => {
    forceScrobbleIfEligible(); // Save progress if backing out

    if (metadataInterval) clearInterval(metadataInterval);
    if (hlsInstance) hlsInstance.destroy();
    StopStream().catch((err) =>
      console.warn("[VideoPlayer] StopStream failed:", err),
    );
  });
</script>

<div class="flex flex-col space-y-4 w-full">
  <div class="flex items-center justify-between">
    <div class="flex flex-col">
      <h3 class="text-xl font-semibold text-main flex items-center">
        Episode {playingEpisode}
      </h3>
    </div>

    <button
      on:click={handleBack}
      class="flex items-center space-x-2 text-sm text-primary hover:text-primary-hover transition-colors"
    >
      <span>&larr; Back to Release List</span>
    </button>
  </div>

  <div
    bind:this={playerContainer}
    class="relative group w-full aspect-video bg-black rounded-xl overflow-hidden border border-zinc-800 shadow-2xl"
  >
    <div class="absolute top-4 right-4 z-50 pointer-events-none">
      {#if hasScrobbled}
        <div
          class="bg-green-500/90 text-white px-4 py-2 rounded-full text-sm font-bold shadow-lg transition-all duration-300"
        >
          Saved to AniList
        </div>
      {:else if isTrackingTimerActive}
        <div
          class="bg-yellow-500/90 text-white px-4 py-2 rounded-full text-sm font-bold shadow-lg transition-all duration-300 flex items-center space-x-2"
        >
          <span class="animate-spin text-lg leading-none">↻</span>
          <span>Tracking...</span>
        </div>
      {/if}
    </div>

    <video
      bind:this={videoElement}
      bind:paused
      bind:currentTime
      bind:volume
      bind:muted={isMuted}
      on:click={togglePlay}
      preload="none"
      crossorigin="anonymous"
      class="w-full h-full object-contain"
    >
      <track kind="captions" />
    </video>

    <div
      class="absolute bottom-0 left-0 right-0 p-4 bg-gradient-to-t from-black/90 via-black/40 to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex flex-col gap-2"
    >
      <input
        type="range"
        min="0"
        max={duration || 0}
        bind:value={currentTime}
        class="w-full h-1 bg-zinc-600 rounded-lg appearance-none cursor-pointer accent-white"
      />
      <div class="flex items-center justify-between text-white text-sm">
        <div class="flex items-center gap-4">
          <button
            on:click={togglePlay}
            class="hover:text-zinc-300 transition-colors w-8"
          >
            {#if paused}
              <svg viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6"
                ><path d="M8 5v14l11-7z" /></svg
              >
            {:else}
              <svg viewBox="0 0 24 24" fill="currentColor" class="w-6 h-6"
                ><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z" /></svg
              >
            {/if}
          </button>

          <div class="font-mono tabular-nums">
            {formatTime(currentTime)} / {formatTime(duration)}
          </div>
        </div>

        <div class="flex items-center gap-4">
          <div class="flex items-center gap-2 group/volume">
            <button
              on:click={toggleMute}
              class="hover:text-zinc-300 transition-colors"
            >
              {#if isMuted || volume === 0}
                <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5"
                  ><path
                    d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z"
                  /></svg
                >
              {:else}
                <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5"
                  ><path
                    d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02z"
                  /></svg
                >
              {/if}
            </button>
            <input
              type="range"
              min="0"
              max="1"
              step="0.05"
              bind:value={volume}
              class="w-0 group-hover/volume:w-20 transition-all duration-300 h-1 bg-zinc-600 rounded-lg appearance-none cursor-pointer accent-white overflow-hidden"
            />
          </div>

          <button
            on:click={toggleFullscreen}
            class="hover:text-zinc-300 transition-colors"
          >
            <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5"
              ><path
                d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z"
              /></svg
            >
          </button>
        </div>
      </div>
    </div>
  </div>
</div>
