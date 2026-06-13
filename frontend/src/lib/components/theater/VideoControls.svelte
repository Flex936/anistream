<script lang="ts">
  import {
    Play,
    Pause,
    Volume2,
    Volume1,
    VolumeX,
    Maximize,
    Settings,
  } from "@lucide/svelte";

  // ── Props ───────────────────────────────────────────────────────────────────
  // All media-state props are READ-ONLY — they come from GetMpvMetadata() polling
  // in VideoPlayer.  User interactions fire callbacks instead of using bind:.
  let {
    paused = false,
    currentTime = 0,
    duration = 0,
    volume = 1, // 0–1 (VideoPlayer converts to/from MPV's 0–100)
    isMuted = false,
    isIdle = false,
    settingsOpen = $bindable(false),
    onToggle,
    onSeek,
    onVolumeChange, // (vol01: number) => void  — 0–1
    onMuteToggle,
    onFullscreen,
  }: {
    paused?: boolean;
    currentTime?: number;
    duration?: number;
    volume?: number;
    isMuted?: boolean;
    isIdle?: boolean;
    settingsOpen?: boolean;
    onToggle?: () => void;
    onSeek?: (seconds: number) => void;
    onVolumeChange?: (vol01: number) => void;
    onMuteToggle?: () => void;
    onFullscreen?: () => void;
  } = $props();

  // ── Seek scrubbing ──────────────────────────────────────────────────────────
  // While the user drags the seek bar we show the dragged value ("scrubValue")
  // rather than the polled currentTime so the bar doesn't jump around.
  // On pointer-up we commit by calling onSeek(), then release the override.
  let isScrubbing = $state(false);
  let scrubValue = $state(0);

  $effect(() => {
    if (!isScrubbing) scrubValue = currentTime;
  });

  function handleSeekPointerDown() {
    isScrubbing = true;
  }

  function handleSeekInput(e: Event) {
    scrubValue = parseFloat((e.target as HTMLInputElement).value);
  }

  function handleSeekPointerUp(e: Event) {
    const v = parseFloat((e.target as HTMLInputElement).value);
    isScrubbing = false;
    onSeek?.(v);
  }

  // ── Volume ──────────────────────────────────────────────────────────────────
  function handleVolumeInput(e: Event) {
    onVolumeChange?.(parseFloat((e.target as HTMLInputElement).value));
  }

  // ── Time formatting ─────────────────────────────────────────────────────────
  function formatTime(s: number): string {
    if (!isFinite(s) || isNaN(s) || s < 0) return "0:00";
    const m = Math.floor(s / 60);
    const sec = Math.floor(s % 60);
    return `${m}:${sec.toString().padStart(2, "0")}`;
  }

  // Display the scrub-preview time when dragging, otherwise the polled time.
  let displayTime = $derived(isScrubbing ? scrubValue : currentTime);
</script>

<!--
  Controls bar: fades out when isIdle and player is active.
  The player-scrim gradient provides a readability backdrop without blocking video.
-->
<div
  class="absolute bottom-0 left-0 right-0 p-4 player-scrim flex flex-col gap-2
         transition-opacity duration-300
         {isIdle ? 'opacity-0 pointer-events-none' : 'opacity-100'}"
>
  <!-- ── Seek bar ──────────────────────────────────────────────────────────── -->
  <input
    type="range"
    min="0"
    max={duration || 0}
    value={scrubValue}
    oninput={handleSeekInput}
    onpointerdown={handleSeekPointerDown}
    onpointerup={handleSeekPointerUp}
    class="w-full h-1 bg-zinc-600 rounded-lg appearance-none cursor-pointer accent-white"
  />

  <!-- ── Bottom row ───────────────────────────────────────────────────────── -->
  <div class="flex items-center justify-between text-white text-sm mt-1">
    <!-- Left: play/pause + timestamp -->
    <div class="flex items-center gap-4">
      <button
        onclick={() => onToggle?.()}
        class="hover:text-zinc-300 transition-colors w-8 flex justify-center hover:cursor-pointer"
        aria-label={paused ? "Play" : "Pause"}
      >
        {#if paused}
          <Play size={22} fill="currentColor" />
        {:else}
          <Pause size={22} fill="currentColor" />
        {/if}
      </button>

      <span class="font-mono tabular-nums select-none">
        {formatTime(displayTime)} / {formatTime(duration)}
      </span>
    </div>

    <!-- Right: volume + mute + settings + fullscreen -->
    <div class="flex items-center gap-4">
      <!-- Mute button -->
      <button
        onclick={() => onMuteToggle?.()}
        class="text-white hover:text-primary transition-colors focus:outline-none hover:cursor-pointer"
        title={isMuted ? "Unmute" : "Mute"}
        aria-label={isMuted ? "Unmute" : "Mute"}
      >
        {#if isMuted || volume === 0}
          <VolumeX size={20} class="drop-shadow-md" />
        {:else if volume < 0.5}
          <Volume1 size={20} class="drop-shadow-md" />
        {:else}
          <Volume2 size={20} class="drop-shadow-md" />
        {/if}
      </button>

      <!-- Volume slider -->
      <div class="w-24 flex items-center">
        <input
          type="range"
          min="0"
          max="1"
          step="0.01"
          value={isMuted ? 0 : volume}
          oninput={handleVolumeInput}
          class="w-full h-1.5 bg-zinc-600/80 rounded-full appearance-none cursor-pointer
                 accent-primary focus:outline-none transition-all shadow-inner"
          aria-label="Volume"
        />
      </div>

      <!-- Settings toggle -->
      <button
        onclick={() => (settingsOpen = !settingsOpen)}
        class="hover:text-zinc-300 transition-colors ml-2 hover:cursor-pointer"
        aria-label="Settings"
      >
        <Settings size={20} />
      </button>

      <!-- Fullscreen -->
      <button
        onclick={() => onFullscreen?.()}
        class="hover:text-zinc-300 transition-colors ml-2 hover:cursor-pointer"
        aria-label="Fullscreen"
      >
        <Maximize size={20} />
      </button>
    </div>
  </div>
</div>
