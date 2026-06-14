<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { LoaderCircle } from "@lucide/svelte";
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

  // ==========================================
  // CONFIGURATION & PROPS
  // ==========================================

  let {
    streamUrl = null,
    playingEpisode,
    animeId,
    isLoggedIn = false,
    onBack,
  }: {
    streamUrl?: string | null;
    playingEpisode: number;
    animeId: number;
    isLoggedIn?: boolean;
    onBack?: () => void;
  } = $props();

  const HLS_CONFIG = {
    maxBufferLength: 60,
    liveSyncDurationCount: 3,
    fragLoadingTimeOut: 120000,
    manifestLoadingTimeOut: 120000,
    fragLoadingMaxRetry: 999,
    manifestLoadingMaxRetry: 999,
    levelLoadingMaxRetry: 999,
    fragLoadingRetryDelay: 100,
    manifestLoadingRetryDelay: 1000,
    startPosition: 0,
  };

  // ==========================================
  // DOM & CORE STATE
  // ==========================================

  let hlsInstance: Hls | undefined;
  let videoElement: HTMLVideoElement;
  let playerContainer: HTMLDivElement;

  let currentTime = $state(0);
  let duration = $state(0);
  let volume = $state(1);
  let isMuted = $state(false);
  let paused = $state(true);

  let isVideoStalled = $state(true);
  let isBuffering = $derived(!streamUrl || isVideoStalled);
  let userWantsToPlay = $state(true);
  let isPlayPending = false;

  // ==========================================
  // UI & TRACKING STATE
  // ==========================================

  let SettingsOpen = $state(false);
  let isIdle = $state(false);
  let animeData = $state<mpv.FrontendPayload | undefined>();

  let SelectedSub = $derived(animeData?.subtitles.find((x) => x.selected));
  let SelectedAudio = $derived(animeData?.audio_tracks.find((x) => x.selected));

  let currentProgress = $state(0);
  let hasScrobbled = $state(false);
  let isTrackingTimerActive = $state(false);

  // ==========================================
  // TIMERS
  // ==========================================

  let trackingTimeout: ReturnType<typeof setTimeout>;
  let watchdogInterval: ReturnType<typeof setInterval>;
  let metadataInterval: ReturnType<typeof setInterval>;
  let idleTimeout: ReturnType<typeof setTimeout>;

  // ==========================================
  // LIFECYCLES & WATCHERS
  // ==========================================

  onMount(() => {
    startMetadataLoop();
    startWatchdog();
  });

  onDestroy(() => {
    clearInterval(watchdogInterval);
    clearAllTimers();
    hlsInstance?.destroy();
    StopStream().catch(console.warn);
  });

  // Init player when stream URL arrives
  $effect(() => {
    if (streamUrl && videoElement) initPlayer();
  });

  // Init AniList tracker state
  $effect(() => {
    if (isLoggedIn && animeId && playingEpisode) initScrobbler();
  });

  // Synchronize custom UI controls with user intent
  $effect(() => {
    if (paused !== !userWantsToPlay) {
      userWantsToPlay = !paused;
      if (userWantsToPlay) attemptAutoplay();
      else videoElement?.pause();
    }
  });

  // ==========================================
  // HLS & PLAYER ENGINE
  // ==========================================

  function initPlayer(): void {
    if (!streamUrl || !videoElement) return;
    hlsInstance?.destroy();

    if (!Hls.isSupported()) {
      if (videoElement.canPlayType("application/vnd.apple.mpegurl")) {
        videoElement.src = streamUrl;
      }
      return;
    }

    hlsInstance = new Hls(HLS_CONFIG);
    hlsInstance.loadSource(streamUrl);
    hlsInstance.attachMedia(videoElement);
    hlsInstance.on(Hls.Events.MANIFEST_PARSED, attemptAutoplay);
    hlsInstance.on(Hls.Events.ERROR, handleHlsError);
  }

  function handleHlsError(_event: any, data: any) {
    console.log(`handleHlsError: ${data}`);
    switch (data.details) {
      case Hls.ErrorDetails.BUFFER_STALLED_ERROR:
        console.log("BUFFER_STALLED_ERROR");
        if (userWantsToPlay && videoElement) videoElement.currentTime += 0.001;
        attemptAutoplay();
        break;

      case Hls.ErrorDetails.BUFFER_APPEND_ERROR:
      case Hls.ErrorDetails.BUFFER_APPENDING_ERROR:
        console.log("BUFFER_APPEND_ERROR or BUFFER_APPENDING_ERROR");
        hlsInstance?.recoverMediaError();
        break;
    }

    if (!data.fatal) {
      console.log("Fatal error");
      return;
    }

    switch (data.type) {
      case Hls.ErrorTypes.NETWORK_ERROR:
        console.log("NETWORK_ERROR");
        hlsInstance?.startLoad();
        if (userWantsToPlay) attemptAutoplay();
        break;

      case Hls.ErrorTypes.MEDIA_ERROR:
        console.log("MEDIA_ERROR");
        hlsInstance?.recoverMediaError();
        if (userWantsToPlay) attemptAutoplay();
        break;

      default:
        console.log("Unknown error");
        initPlayer();
        break;
    }
  }

  async function attemptAutoplay(): Promise<void> {
    if (!videoElement || !streamUrl || isPlayPending) return;
    isPlayPending = true;

    try {
      await videoElement.play();
      paused = false;
      isMuted = false;
    } catch {
      try {
        isMuted = true;
        await videoElement.play();
        paused = false;
        setTimeout(() => {
          isMuted = false;
        }, 300);
      } catch {
        paused = true;
      }
    } finally {
      isPlayPending = false;
    }
  }

  // ==========================================
  // DOM EVENT HANDLERS
  // ==========================================

  function togglePlayState() {
    userWantsToPlay = !userWantsToPlay;
    paused = !userWantsToPlay;
    if (userWantsToPlay) attemptAutoplay();
    else videoElement?.pause();
  }

  function handleTimeUpdate() {
    checkScrobbler(currentTime, duration);
  }

  function startWatchdog(): void {
    clearInterval(watchdogInterval);
    watchdogInterval = setInterval(() => {
      if (!videoElement || !streamUrl) return;

      if (userWantsToPlay && videoElement.paused && !isPlayPending) {
        attemptAutoplay();
      }
    }, 1000);
  }

  function resetIdleTimer() {
    isIdle = false;
    clearTimeout(idleTimeout);
    if (!paused && !SettingsOpen) {
      idleTimeout = setTimeout(() => {
        isIdle = true;
      }, 2500);
    }
  }

  function forceIdle() {
    if (!paused && !SettingsOpen) {
      isIdle = true;
      clearTimeout(idleTimeout);
    }
  }

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
        togglePlayState();
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

  function toggleFullscreen(): void {
    if (!document.fullscreenElement)
      playerContainer.requestFullscreen().catch(console.error);
    else document.exitFullscreen();
  }

  // ==========================================
  // SCROBBLER & BUSINESS LOGIC
  // ==========================================

  async function initScrobbler(): Promise<void> {
    hasScrobbled = false;
    isTrackingTimerActive = false;
    clearTimeout(trackingTimeout);
    try {
      currentProgress = await GetAnimeProgress(animeId);
    } catch (err) {
      console.error("Scrobbler init failed:", err);
    }
  }

  function checkScrobbler(time: number, maxTime: number) {
    if (maxTime <= 0 || hasScrobbled) return;

    if (time / maxTime >= 0.9) {
      if (!isTrackingTimerActive && playingEpisode > currentProgress) {
        isTrackingTimerActive = true;
        trackingTimeout = setTimeout(async () => {
          if (currentTime / duration >= 0.9) await commitScrobble();
          else isTrackingTimerActive = false;
        }, 5000);
      }
    } else if (isTrackingTimerActive) {
      clearTimeout(trackingTimeout);
      isTrackingTimerActive = false;
    }
  }

  async function commitScrobble(): Promise<void> {
    hasScrobbled = true;
    isTrackingTimerActive = false;
    try {
      await UpdateAnimeProgress(animeId, playingEpisode);
    } catch {
      hasScrobbled = false;
    }
  }

  function flushScrobbler(): void {
    clearTimeout(trackingTimeout);
    if (
      isLoggedIn &&
      !hasScrobbled &&
      duration > 0 &&
      playingEpisode > currentProgress &&
      currentTime / duration >= 0.9
    ) {
      commitScrobble();
    }
  }

  function startMetadataLoop(): void {
    clearInterval(metadataInterval);
    metadataInterval = setInterval(async () => {
      try {
        const data = await GetMpvMetadata();
        if (data?.duration > 0) {
          animeData = data;
          duration = data.duration;
        }
      } catch {}
    }, 1000);
  }

  async function handleTrackChange(sid: string, aid: string): Promise<void> {
    const savedTime = currentTime;
    clearInterval(metadataInterval);
    try {
      await ChangeTrackAndRestart(savedTime, sid, aid);
    } catch (err) {
      console.error("Track change failed:", err);
    } finally {
      startMetadataLoop();
      initPlayer();
    }
  }

  function handleBack(): void {
    flushScrobbler();
    onBack?.();
  }

  function clearAllTimers() {
    clearInterval(metadataInterval);
    clearTimeout(trackingTimeout);
    clearTimeout(idleTimeout);
  }
</script>

<svelte:window onkeydown={handleKeyDown} />

<div class="flex flex-col space-y-4 w-full">
  <VideoHeader {playingEpisode} onBack={handleBack} />

  <div
    bind:this={playerContainer}
    onpointermove={resetIdleTimer}
    onpointerleave={forceIdle}
    aria-label="video-player"
    role="dialog"
    tabindex="0"
    class="relative w-full aspect-video bg-black rounded-xl overflow-hidden
           border border-zinc-800 shadow-2xl {isIdle ? 'cursor-none' : ''}"
  >
    {#if isLoggedIn}
      <TrackingOverlay {hasScrobbled} {isTrackingTimerActive} />
    {/if}

    {#if isBuffering}
      <div
        class="absolute inset-0 flex flex-col items-center justify-center pointer-events-none z-10 bg-black/40 backdrop-blur-sm"
      >
        <LoaderCircle
          size={64}
          class="animate-spin text-primary opacity-80 mb-4"
        />
        {#if !streamUrl}
          <span class="text-white font-bold text-lg drop-shadow-md"
            >Starting Stream Engine...</span
          >
        {:else}
          <span class="text-white font-bold text-lg drop-shadow-md"
            >Buffering...</span
          >
        {/if}
      </div>
    {/if}

    <video
      bind:this={videoElement}
      bind:currentTime
      bind:volume
      bind:muted={isMuted}
      onwaiting={() => (isVideoStalled = true)}
      onplaying={() => {
        isVideoStalled = false;
        paused = false;
      }}
      onpause={() => {
        if (!userWantsToPlay) paused = true;
      }}
      oncanplay={() => {
        isVideoStalled = false;
        if (userWantsToPlay && videoElement.paused) attemptAutoplay();
      }}
      ontimeupdate={handleTimeUpdate}
      onclick={togglePlayState}
      preload="none"
      crossorigin="anonymous"
      class="w-full h-full object-contain cursor-auto"
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
