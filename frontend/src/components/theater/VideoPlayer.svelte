<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import {
    GetAnimeProgress,
    UpdateAnimeProgress,
    StopStream,
    GetMpvMetadata,
    SendMpvCommand,
    ChangeTrackAndRestart,
  } from "../../../wailsjs/go/main/App";
  import Hls from "hls.js";

  import VideoHeader from "./VideoHeader.svelte";
  import TrackingOverlay from "./TrackingOverlay.svelte";
  import VideoControls from "./VideoControls.svelte";
  import VideoSettings from "./VideoSettings.svelte";

  import type { main } from "../../../wailsjs/go/models";

  let {
    streamUrl,
    playingEpisode,
    animeId,
    onBack,
  }: {
    streamUrl: string;
    playingEpisode: number;
    animeId: number;
    onBack?: () => void;
  } = $props();

  // AniList State
  let currentProgress = $state(0);
  let hasScrobbled = $state(false);
  let isTrackingTimerActive = $state(false);
  let trackingTimeout: ReturnType<typeof setTimeout>;

  // Shared Video State
  let currentTime = $state(0);
  let duration = $state(0);

  // Player State
  let hlsInstance: Hls | undefined;
  let videoElement: HTMLVideoElement;
  let playerContainer: HTMLDivElement;
  let paused = $state(true);
  let volume = $state(1);
  let isMuted = $state(false);
  let metadataInterval: ReturnType<typeof setInterval>;
  let SettingsOpen = $state(false);
  let animeData = $state<main.FrontendPayload | undefined>(undefined);

  // ==========================================
  // AniList Tracking Logic (kept exactly as is)
  // ==========================================
  $effect(() => {
    if (animeId && playingEpisode) {
      resetTracker();
    }
  });

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

  $effect(() => {
    if (duration > 0 && !hasScrobbled) {
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
  });

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
    onBack?.();
  }

  // ==========================================
  // Player & HLS Logic
  // ==========================================
  async function fetchMetadata() {
    try {
      const res = await GetMpvMetadata();
      if (!res) return;
      const data = await res;
      if (data && data.duration > 0) {
        animeData = data;
        duration = data.duration;
      }
    } catch (err) {
      /* wait */
    }
  }

  let SelectedSub = $derived(animeData?.subtitles.find((x) => x.selected));
  let SelectedAudio = $derived(animeData?.audio_tracks.find((x) => x.selected));

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

  // 2. Handle stream reconstruction on track switch
  async function handleTrackChange(sid: string, aid: string) {
    try {
      // Capture the timestamp right before killing the stream pipeline
      const currentTimestamp = currentTime;

      // Temporary pause metadata loop during reconstruction
      clearInterval(metadataInterval);

      // Request backend restart
      await ChangeTrackAndRestart(currentTimestamp, sid, aid);

      // Re-trigger metadata fetching
      metadataInterval = setInterval(fetchMetadata, 1000);

      // Force-reinitialize hls.js to fetch the brand new playlist chunks
      initPlayer();
    } catch (err) {
      console.error("Failed to alter active stream tracks:", err);
    }
  }

  $effect(() => {
    if (streamUrl && videoElement) initPlayer();
  });

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
  <VideoHeader {playingEpisode} onBack={handleBack} />

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
      onclick={() => (paused = !paused)}
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
      bind:SettingsOpen
      onFullscreen={toggleFullscreen}
    />

    <VideoSettings
      bind:SettingsOpen
      {animeData}
      {SelectedSub}
      {SelectedAudio}
      OnTrackChange={handleTrackChange}
    />
  </div>
</div>
