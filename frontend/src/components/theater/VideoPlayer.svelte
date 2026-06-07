<script lang="ts">
  import { createEventDispatcher, onMount, onDestroy } from "svelte";
  import {
    GetAnimeProgress,
    UpdateAnimeProgress,
    StopStream,
  } from "../../../wailsjs/go/main/App";
  import Hls from "hls.js";

  import VideoHeader from "./VideoHeader.svelte";
  import TrackingOverlay from "./TrackingOverlay.svelte";
  import VideoControls from "./VideoControls.svelte";

  // Props
  export let streamUrl: string;
  export let playingEpisode: number;
  export let animeId: number;

  const dispatch = createEventDispatcher();

  // AniList State
  let currentProgress = 0;
  let hasScrobbled = false;
  let isTrackingTimerActive = false;
  let trackingTimeout: ReturnType<typeof setTimeout>;

  // Shared Video State
  let currentTime = 0;
  let duration = 0;

  // Player State
  let hlsInstance: Hls | undefined;
  let videoElement: HTMLVideoElement;
  let playerContainer: HTMLDivElement;
  let paused = true;
  let volume = 1;
  let isMuted = false;
  let metadataInterval: ReturnType<typeof setInterval>;

  // ==========================================
  // AniList Tracking Logic
  // ==========================================
  $: if (animeId && playingEpisode) resetTracker();

  async function resetTracker() {
    hasScrobbled = false;
    isTrackingTimerActive = false;
    clearTimeout(trackingTimeout);
    try {
      currentProgress = await GetAnimeProgress(animeId);
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
          if (currentTime / duration >= 0.9) await triggerAniListUpdate();
          else isTrackingTimerActive = false;
        }, 5000);
      }
    } else if (isTrackingTimerActive) {
      clearTimeout(trackingTimeout);
      isTrackingTimerActive = false;
    }
  }

  async function triggerAniListUpdate() {
    hasScrobbled = true;
    isTrackingTimerActive = false;
    try {
      await UpdateAnimeProgress(animeId, playingEpisode);
    } catch (err) {
      hasScrobbled = false;
    }
  }

  function handleBack() {
    clearTimeout(trackingTimeout);
    if (
      !hasScrobbled &&
      duration > 0 &&
      playingEpisode > currentProgress &&
      currentTime / duration >= 0.9
    ) {
      triggerAniListUpdate();
    }
    dispatch("back");
  }

  // ==========================================
  // Player & HLS Logic
  // ==========================================
  async function fetchMetadata() {
    try {
      const res = await fetch("http://localhost:8080/anime-data");
      if (!res.ok) return;
      const data = await res.json();
      if (data && data.duration > 0) {
        clearInterval(metadataInterval);
        duration = data.duration;
      }
    } catch (err) {
      /* wait */
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
        liveSyncDurationCount: 1,
        manifestLoadingMaxRetry: 10,
        manifestLoadingRetryDelay: 500,
        fragLoadingMaxRetry: 10,
        fragLoadingRetryDelay: 500,
      });

      hlsInstance.loadSource(streamUrl);
      hlsInstance.attachMedia(videoElement);

      hlsInstance.on(Hls.Events.MANIFEST_PARSED, () => {
        videoElement
          .play()
          .then(() => (paused = false))
          .catch(() => (paused = true));
      });

      hlsInstance.on(Hls.Events.ERROR, (event, data) => {
        if (data.fatal) {
          if (data.type === Hls.ErrorTypes.NETWORK_ERROR)
            setTimeout(() => hlsInstance?.startLoad(), 1000);
          else if (data.type === Hls.ErrorTypes.MEDIA_ERROR)
            hlsInstance?.recoverMediaError();
          else initPlayer();
        }
      });
    }
  }

  $: if (streamUrl && videoElement) initPlayer();

  function toggleFullscreen() {
    if (!document.fullscreenElement)
      playerContainer.requestFullscreen().catch(console.error);
    else document.exitFullscreen();
  }

  onMount(() => {
    metadataInterval = setInterval(fetchMetadata, 1000);
  });

  onDestroy(() => {
    if (metadataInterval) clearInterval(metadataInterval);
    if (hlsInstance) hlsInstance.destroy();
    StopStream().catch(console.warn);
  });
</script>

<div class="flex flex-col space-y-4 w-full">
  <VideoHeader {playingEpisode} on:back={handleBack} />

  <div
    bind:this={playerContainer}
    class="relative group w-full aspect-video bg-black rounded-xl overflow-hidden border border-zinc-800 shadow-2xl"
  >
    <TrackingOverlay {hasScrobbled} {isTrackingTimerActive} />

    <video
      bind:this={videoElement}
      bind:paused
      bind:currentTime
      bind:volume
      bind:muted={isMuted}
      on:click={() => (paused = !paused)}
      preload="none"
      crossorigin="anonymous"
      class="w-full h-full object-contain cursor-pointer"
    >
      <track kind="captions" />
    </video>

    <VideoControls
      bind:paused
      bind:currentTime
      {duration}
      bind:volume
      bind:isMuted
      on:fullscreen={toggleFullscreen}
    />
  </div>
</div>
