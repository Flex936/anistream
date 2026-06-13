<script lang="ts">
  /**
   * VideoPlayer.svelte — the "glass pane"
   *
   * Architecture
   * ────────────
   * There is NO <video> element and NO hls.js.  MPV is rendering natively BELOW
   * this component via --wid (HWND on Windows, X11 XID on Linux, NSView on macOS).
   *
   * This component is a fixed full-viewport transparent overlay (z-[100]).
   * All UI elements sit on top of the transparent background; the native video
   * layer shows through everywhere else.
   *
   * Theatre-mode CSS
   * ────────────────
   * On mount we add `theater-mode` to <html>.  style.css uses that class to make
   * #app and <main> transparent so nothing blocks the native render layer.
   * The class is removed on destroy to restore normal backgrounds.
   *
   * Stream lifecycle
   * ────────────────
   * VideoPlayer does NOT call StopStream().  Stream lifecycle is owned by
   * TheaterView.svelte — VideoPlayer just fires onBack() when the user leaves.
   */

  import { onMount, onDestroy } from "svelte";
  import { LoaderCircle } from "@lucide/svelte";
  import {
    GetAnimeProgress,
    UpdateAnimeProgress,
    GetMpvMetadata,
    ToggleMPV,
    SeekMPV,
    SetVolumeMPV,
    ToggleMuteMPV,
    SetSubtitleMPV,
    SetAudioTrackMPV,
    ToggleFullscreen,
  } from "$wails/go/main/App";
  import type { mpv } from "$wails/go/models";

  import VideoHeader from "$lib/components/theater/VideoHeader.svelte";
  import TrackingOverlay from "$lib/components/theater/TrackingOverlay.svelte";
  import VideoControls from "$lib/components/theater/VideoControls.svelte";
  import VideoSettings from "$lib/components/theater/VideoSettings.svelte";

  // ── Props ─────────────────────────────────────────────────────────────────
  let {
    playingEpisode,
    animeId,
    isLoggedIn = false,
    isLoading = false,
    onBack,
  }: {
    playingEpisode: number;
    animeId: number;
    isLoggedIn?: boolean;
    isLoading?: boolean;
    onBack?: () => void;
  } = $props();

  // ── Playback state — sourced entirely from GetMpvMetadata() polling ────────
  // These values no longer come from a <video> element; they are pushed to us
  // by the Go backend which reads them from the MPV IPC socket every ~500 ms.
  let paused = $state(false);
  let currentTime = $state(0);
  let duration = $state(0);
  let volume = $state(1); // 0–1 for UI sliders; MPV works in 0–100
  let isMuted = $state(false);
  let animeData = $state<mpv.FrontendPayload | undefined>(undefined);

  // ── UI state ──────────────────────────────────────────────────────────────
  let isIdle = $state(false);
  let settingsOpen = $state(false);
  let metadataInterval: ReturnType<typeof setInterval>;
  let idleTimeout: ReturnType<typeof setTimeout>;

  // ── AniList progress tracking ──────────────────────────────────────────────
  let currentProgress = $state(0);
  let hasScrobbled = $state(false);
  let isTrackingTimerActive = $state(false);
  let trackingTimeout: ReturnType<typeof setTimeout>;

  // ── Derived track selection ────────────────────────────────────────────────
  let SelectedSub = $derived(animeData?.subtitles.find((x) => x.selected));
  let SelectedAudio = $derived(animeData?.audio_tracks.find((x) => x.selected));

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  onMount(() => {
    // Theatre mode: make the native MPV render layer visible through the app.
    document.documentElement.classList.add("theater-mode");
    startMetadataPolling();
    if (isLoggedIn && animeId && playingEpisode) resetTracker();
  });

  onDestroy(() => {
    // Restore normal app backgrounds.
    document.documentElement.classList.remove("theater-mode");
    clearInterval(metadataInterval);
    clearTimeout(idleTimeout);
    clearTimeout(trackingTimeout);
    // Note: StopStream() is intentionally NOT called here.
    // Stream lifecycle belongs to TheaterView.svelte.
  });

  // ── Metadata polling ───────────────────────────────────────────────────────
  // Replaces the <video> element's timeupdate / volumechange / pause events.
  function startMetadataPolling(): void {
    clearInterval(metadataInterval);
    metadataInterval = setInterval(async () => {
      try {
        const data = await GetMpvMetadata();
        if (!data) return;
        animeData = data;
        duration = data.duration;
        currentTime = data.time_pos;
        paused = data.paused;
        isMuted = data.muted;
        volume = data.volume / 100; // MPV 0–100 → UI 0–1
      } catch {
        /* MPV IPC not yet ready — silently retry next tick */
      }
    }, 500);
  }

  // ── Idle / cursor autohide ────────────────────────────────────────────────
  function handlePointerMove(): void {
    isIdle = false;
    clearTimeout(idleTimeout);
    if (!paused && !settingsOpen) {
      idleTimeout = setTimeout(() => {
        isIdle = true;
      }, 2500);
    }
  }

  function handlePointerLeave(): void {
    if (!paused && !settingsOpen) {
      isIdle = true;
      clearTimeout(idleTimeout);
    }
  }

  // ── Playback control callbacks ─────────────────────────────────────────────
  // Each handler updates local state optimistically so the UI responds instantly,
  // then fires the IPC command.  If the command fails it reverts.

  async function handleToggle(): Promise<void> {
    paused = !paused;
    await ToggleMPV().catch(() => {
      paused = !paused;
    });
  }

  async function handleSeek(seconds: number): Promise<void> {
    currentTime = seconds;
    await SeekMPV(seconds).catch(console.error);
  }

  async function handleVolumeChange(vol01: number): Promise<void> {
    volume = vol01;
    await SetVolumeMPV(Math.round(vol01 * 100)).catch(console.error);
  }

  async function handleMuteToggle(): Promise<void> {
    isMuted = !isMuted;
    await ToggleMuteMPV().catch(() => {
      isMuted = !isMuted;
    });
  }

  async function handleFullscreen(): Promise<void> {
    // ToggleFullscreen() is a void Go function; no return value to handle.
    await ToggleFullscreen().catch(console.error);
  }

  // ── Track changes — pure IPC, no MPV restart required ─────────────────────
  // This replaces the old ChangeTrackAndRestart() which had to tear down and
  // rebuild the entire HLS pipeline whenever the user switched subtitle/audio.
  async function handleTrackChange(sid: string, aid: string): Promise<void> {
    try {
      await SetSubtitleMPV(sid);
      await SetAudioTrackMPV(aid);
    } catch (err) {
      console.error("Track change IPC failed:", err);
    }
  }

  // ── Back button ────────────────────────────────────────────────────────────
  function handleBack(): void {
    clearTimeout(trackingTimeout);
    // Scrobble on exit if the 90 % threshold was already met but the
    // 5-second confirmation timer hadn't fired yet.
    if (
      isLoggedIn &&
      !hasScrobbled &&
      duration > 0 &&
      playingEpisode > currentProgress &&
      currentTime / duration >= 0.9
    ) {
      void triggerAniListUpdate();
    }
    onBack?.();
  }

  // ── AniList 90 % threshold tracking ───────────────────────────────────────
  $effect(() => {
    if (isLoggedIn && animeId && playingEpisode) resetTracker();
  });

  async function resetTracker(): Promise<void> {
    hasScrobbled = false;
    isTrackingTimerActive = false;
    clearTimeout(trackingTimeout);
    try {
      currentProgress = await GetAnimeProgress(animeId);
    } catch (err) {
      console.error("Failed to fetch AniList progress:", err);
    }
  }

  // Note: no cleanup returned here intentionally — see VideoPlayer.svelte
  // comments in the original codebase for the reasoning.
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

  // ── Keyboard shortcuts ─────────────────────────────────────────────────────
  function handleKeyDown(event: KeyboardEvent): void {
    const tag = (event.target as HTMLElement).tagName;
    if (tag === "INPUT" || tag === "TEXTAREA") return;
    switch (event.key) {
      case " ":
        event.preventDefault();
        void handleToggle();
        break;
      case "ArrowLeft":
        event.preventDefault();
        void handleSeek(Math.max(0, currentTime - 5));
        break;
      case "ArrowRight":
        event.preventDefault();
        void handleSeek(Math.min(duration, currentTime + 5));
        break;
      case "ArrowUp":
        event.preventDefault();
        void handleVolumeChange(Math.min(1, volume + 0.1));
        break;
      case "ArrowDown":
        event.preventDefault();
        void handleVolumeChange(Math.max(0, volume - 0.1));
        break;
      case "Escape":
        handleBack();
        break;
    }
  }
</script>

<svelte:window onkeydown={handleKeyDown} />

<!--
  ═══════════════════════════════════════════════════════════════
  THE GLASS PANE
  ═══════════════════════════════════════════════════════════════
  fixed inset-0 z-[100]:
    Covers the entire viewport including NavBar (z-50).
    Higher z-index wins; NavBar input is intentionally blocked in theater mode.

  background: transparent:
    This is the critical property.  The OS compositor shows whatever is below
    the WebView where no opaque Svelte element is rendered.  In theater mode
    that "below" layer is the native MPV video surface embedded via --wid.

  cursor-none when idle:
    Hides the OS cursor so the video fills without distraction.
  ═══════════════════════════════════════════════════════════════
-->
<div
  class="fixed inset-0 z-[100] select-none {isIdle ? 'cursor-none' : ''}"
  style="background: transparent;"
  onpointermove={handlePointerMove}
  onpointerleave={handlePointerLeave}
  role="region"
  aria-label="Video player controls"
>
  {#if isLoading || !animeData}
    <div
      class="absolute inset-0 bg-black z-[120] flex flex-col items-center justify-center text-white"
    >
      <LoaderCircle class="animate-spin mb-4 text-sky-400" size={48} />
      <h2 class="text-xl font-bold">Buffering Stream...</h2>
      <p class="text-zinc-400 mt-2 text-sm">
        Allocating native MPV surface and connecting to peers
      </p>
    </div>
  {/if}

  <div
    class="absolute top-0 left-0 right-0 p-5 player-top-scrim
           transition-opacity duration-300
           {isIdle && !isLoading && animeData
      ? 'opacity-0 pointer-events-none'
      : 'opacity-100'}"
  >
    <VideoHeader {playingEpisode} onBack={handleBack} />
  </div>

  <!-- ── AniList scrobble notification (top-right) ──────────────────────── -->
  {#if isLoggedIn}
    <TrackingOverlay {hasScrobbled} {isTrackingTimerActive} />
  {/if}

  <!-- ── Settings panel (floats above controls bar) ─────────────────────── -->
  <VideoSettings
    bind:SettingsOpen={settingsOpen}
    {animeData}
    {SelectedSub}
    {SelectedAudio}
    OnTrackChange={handleTrackChange}
  />

  <!-- ── Bottom controls (seek bar + transport + volume + settings) ─────── -->
  <VideoControls
    {paused}
    {currentTime}
    {duration}
    {volume}
    {isMuted}
    {isIdle}
    bind:settingsOpen
    onToggle={handleToggle}
    onSeek={handleSeek}
    onVolumeChange={handleVolumeChange}
    onMuteToggle={handleMuteToggle}
    onFullscreen={handleFullscreen}
  />
</div>
