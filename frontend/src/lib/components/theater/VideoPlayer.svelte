<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import {
    GetAnimeProgress,
    UpdateAnimeProgress,
    StopStream,
    GetMpvMetadata,
    ChangeTrackAndRestart,
  } from "$wails/go/main/App";
  import Hls from "hls.js";

  import VideoHeader from "$lib/components/theater/VideoHeader.svelte";
  import TrackingOverlay from "$lib/components/theater/TrackingOverlay.svelte";
  import VideoControls from "$lib/components/theater/VideoControls.svelte";
  import VideoSettings from "$lib/components/theater/VideoSettings.svelte";

  import type { mpv } from "$wails/go/models";

  // ─── Props ──────────────────────────────────────────────────────────────
  let {
    streamUrl,
    playingEpisode,
    animeId,
    // FIX: isLoggedIn is now a prop — App.svelte checks auth once; no polling needed here.
    isLoggedIn = false,
    onBack,
  }: {
    streamUrl: string;
    playingEpisode: number;
    animeId: number;
    isLoggedIn?: boolean;
    onBack?: () => void;
  } = $props();

  // ─── AniList tracking state ─────────────────────────────────────────────
  let currentProgress = $state(0);
  let hasScrobbled = $state(false);
  let isTrackingTimerActive = $state(false);
  let trackingTimeout: ReturnType<typeof setTimeout>;

  // ─── Shared video state ─────────────────────────────────────────────────
  let currentTime = $state(0);
  let duration = $state(0);

  // ─── Player state ───────────────────────────────────────────────────────
  let hlsInstance: Hls | undefined;
  let videoElement: HTMLVideoElement;
  let playerContainer: HTMLDivElement;
  let paused = $state(true);
  let volume = $state(1);
  let isMuted = $state(false);
  let SettingsOpen = $state(false);
  let animeData = $state<mpv.FrontendPayload | undefined>(undefined);
  let metadataInterval: ReturnType<typeof setInterval>;

  // ─── Idle / auto-hide cursor ────────────────────────────────────────────
  let isIdle = $state(false);
  let idleTimeout: ReturnType<typeof setTimeout>;

  function handleMouseMove() {
    isIdle = false;
    clearTimeout(idleTimeout);
    if (!paused && !SettingsOpen) {
      idleTimeout = setTimeout(() => {
        isIdle = true;
      }, 2500);
    }
  }

  function handleMouseLeave() {
    if (!paused && !SettingsOpen) {
      isIdle = true;
      clearTimeout(idleTimeout);
    }
  }

  // ─── Derived track selection ────────────────────────────────────────────
  let SelectedSub = $derived(animeData?.subtitles.find((x) => x.selected));
  let SelectedAudio = $derived(animeData?.audio_tracks.find((x) => x.selected));

  // ─── AniList: reset tracker when episode changes ────────────────────────
  $effect(() => {
    if (isLoggedIn && animeId && playingEpisode) {
      resetTracker();
    }
  });

  async function resetTracker(): Promise<void> {
    hasScrobbled = false;
    isTrackingTimerActive = false;
    clearTimeout(trackingTimeout);
    try {
      currentProgress = await GetAnimeProgress(animeId);
    } catch (err) {
      console.error("Failed to fetch progress:", err);
    }
  }

  // ─── AniList: 90 % threshold tracking ───────────────────────────────────
  // NOTE: We do NOT return a cleanup here on purpose. The cleanup would fire
  // every second (on each currentTime tick) and cancel the pending timeout
  // before it ever fires. Cleanup is handled explicitly in onDestroy and
  // handleBack instead.
  $effect(() => {
    if (duration <= 0 || hasScrobbled) return;

    const pct = currentTime / duration;

    if (pct >= 0.9) {
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
  });

  async function triggerAniListUpdate(): Promise<void> {
    hasScrobbled = true;
    isTrackingTimerActive = false;
    try {
      await UpdateAnimeProgress(animeId, playingEpisode);
    } catch {
      hasScrobbled = false;
    }
  }

  function handleBack(): void {
    clearTimeout(trackingTimeout);
    // Scrobble on the way out if the threshold was met but timer hadn't fired yet
    if (
      isLoggedIn &&
      !hasScrobbled &&
      duration > 0 &&
      playingEpisode > currentProgress &&
      currentTime / duration >= 0.9
    ) {
      triggerAniListUpdate();
    }
    onBack?.();
  }

  // ─── Metadata polling ───────────────────────────────────────────────────
  async function fetchMetadata(): Promise<void> {
    try {
      const data = await GetMpvMetadata();
      if (data?.duration > 0) {
        animeData = data;
        duration = data.duration;
      }
    } catch {
      /* backend not ready yet — silently retry next tick */
    }
  }

  // FIX: extracted helper so both onMount and handleTrackChange use the
  //      exact same loop setup (previously handleTrackChange was missing
  //      the checkAuthStatus call from the original interval).
  function startMetadataLoop(): void {
    clearInterval(metadataInterval);
    metadataInterval = setInterval(fetchMetadata, 1000);
  }

  // ─── HLS player ─────────────────────────────────────────────────────────
  function initPlayer(): void {
    if (!streamUrl || !videoElement) return;
    hlsInstance?.destroy();

    if (Hls.isSupported()) {
      hlsInstance = new Hls({
        startPosition: 0,
        liveMaxLatencyDurationCount: 99999,
        maxBufferLength: 30,
        liveSyncDurationCount: 3,
        manifestLoadingMaxRetry: 10,
        manifestLoadingRetryDelay: 500,
        fragLoadingMaxRetry: 10,
        fragLoadingRetryDelay: 100,
      });
      // ── Diagnostics ─────────────────────────────────────────────────────
      // Remove this block once the stutter is confirmed fixed.
      hlsInstance.on(Hls.Events.MANIFEST_PARSED, (_e, data) => {
        const details = data.levels[0]?.details;
        console.log("[HLS] manifest parsed", {
          live: details?.live,
          fragments: details?.fragments?.length,
          liveSyncPosition: hlsInstance?.liveSyncPosition,
          startPosition: hlsInstance?.startPosition,
        });
      });
      hlsInstance.on(Hls.Events.FRAG_CHANGED, (_e, data) => {
        console.log(
          `[HLS] frag → start:${data.frag.start.toFixed(2)}s sn:${data.frag.sn}`,
        );
      });
      hlsInstance.on(Hls.Events.BUFFER_FLUSHING, (_e, data) => {
        console.log(
          `[HLS] buffer flush [${data.startOffset}–${data.endOffset}]`,
        );
      });
      videoElement.addEventListener("seeking", () =>
        console.log(
          `[Video] seeking → ${videoElement.currentTime.toFixed(3)}s`,
        ),
      );
      videoElement.addEventListener("seeked", () =>
        console.log(
          `[Video] seeked  → ${videoElement.currentTime.toFixed(3)}s`,
        ),
      );
      videoElement.addEventListener("waiting", () =>
        console.log(
          `[Video] waiting  @ ${videoElement.currentTime.toFixed(3)}s`,
        ),
      );
      videoElement.addEventListener("stalled", () =>
        console.log(
          `[Video] stalled  @ ${videoElement.currentTime.toFixed(3)}s`,
        ),
      );
      // ── End diagnostics ──────────────────────────────────────────────────

      hlsInstance.loadSource(streamUrl);
      hlsInstance.attachMedia(videoElement);

      hlsInstance.on(Hls.Events.MANIFEST_PARSED, () => {
        // FIX: set currentTime before autoplay; was calling attemptAutoplay() twice
        if (videoElement) videoElement.currentTime = 0;
        attemptAutoplay();
      });

      hlsInstance.on(Hls.Events.ERROR, (_event, data) => {
        if (!data.fatal) return;
        if (data.type === Hls.ErrorTypes.NETWORK_ERROR)
          setTimeout(() => hlsInstance?.startLoad(), 1000);
        else if (data.type === Hls.ErrorTypes.MEDIA_ERROR)
          hlsInstance?.recoverMediaError();
        else initPlayer();
      });
    } else if (videoElement.canPlayType("application/vnd.apple.mpegurl")) {
      videoElement.src = streamUrl;
    }
  }

  // FIX: handleTrackChange now restarts the loop even on error, and uses
  //      startMetadataLoop() instead of an inline setInterval.
  async function handleTrackChange(sid: string, aid: string): Promise<void> {
    const savedTime = currentTime;
    clearInterval(metadataInterval);
    try {
      await ChangeTrackAndRestart(savedTime, sid, aid);
    } catch (err) {
      console.error("Failed to change tracks:", err);
    } finally {
      // Always restart the loop regardless of success/failure
      startMetadataLoop();
      initPlayer();
    }
  }

  $effect(() => {
    if (streamUrl && videoElement) initPlayer();
  });

  function toggleFullscreen(): void {
    if (!document.fullscreenElement)
      playerContainer.requestFullscreen().catch(console.error);
    else document.exitFullscreen();
  }

  async function attemptAutoplay(): Promise<void> {
    try {
      await videoElement.play();
      currentTime = 0;
      paused = false;
    } catch {
      try {
        videoElement.muted = true;
        isMuted = true;
        await videoElement.play();
        currentTime = 0;
        paused = false;
        setTimeout(() => {
          videoElement.muted = false;
          isMuted = false;
        }, 300);
      } catch {
        paused = true;
      }
    }
  }

  // FIX: clamp volume to [0, 1] — previously arrow keys could push it out of range
  function handleKeyDown(event: KeyboardEvent): void {
    const tag = (event.target as HTMLElement).tagName;
    if (
      tag === "INPUT" ||
      tag === "TEXTAREA" ||
      (event.target as HTMLElement).isContentEditable
    )
      return;

    switch (event.key) {
      case " ":
        event.preventDefault();
        paused = !paused;
        break;
      case "ArrowUp":
        event.preventDefault();
        volume = Math.min(1, volume + 0.1);
        break;
      case "ArrowDown":
        event.preventDefault();
        volume = Math.max(0, volume - 0.1);
        break;
      case "ArrowLeft":
        event.preventDefault();
        currentTime -= 5;
        break;
      case "ArrowRight":
        event.preventDefault();
        currentTime += 5;
        break;
    }
  }

  onMount(() => {
    startMetadataLoop();
  });

  onDestroy(() => {
    clearInterval(metadataInterval);
    // FIX: trackingTimeout was never cleared here — could fire on dead state after unmount
    clearTimeout(trackingTimeout);
    clearTimeout(idleTimeout);
    hlsInstance?.destroy();
    StopStream().catch(console.warn);
  });
</script>

<svelte:window onkeydown={handleKeyDown} />

<div class="flex flex-col space-y-4 w-full">
  <VideoHeader {playingEpisode} onBack={handleBack} />

  <div
    bind:this={playerContainer}
    onpointermove={handleMouseMove}
    onpointerleave={handleMouseLeave}
    aria-label="video-player"
    role="dialog"
    tabindex="0"
    class="relative w-full aspect-video bg-black rounded-xl overflow-hidden
           border border-zinc-800 shadow-2xl
           {isIdle ? 'cursor-none' : ''}"
  >
    {#if isLoggedIn}
      <TrackingOverlay {hasScrobbled} {isTrackingTimerActive} />
    {/if}

    <video
      bind:this={videoElement}
      bind:paused
      bind:currentTime
      bind:volume
      bind:muted={isMuted}
      onclick={() => (paused = !paused)}
      preload="none"
      crossorigin="anonymous"
      class="w-full h-full object-contain cursor-default"
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
      {isIdle}
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
