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

  let {
    paused = $bindable(),
    currentTime = $bindable(),
    duration,
    volume = $bindable(),
    isMuted = $bindable(),
    onFullscreen,
    SettingsOpen = $bindable(),
    isIdle,
  } = $props();

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
  function toggleSettings() {
    SettingsOpen = !SettingsOpen;
  }
</script>

<div
  class="absolute bottom-0 left-0 right-0 p-4 bg-linear-to-t from-black/90 via-black/40 to-transparent transition-opacity duration-300 flex flex-col gap-2 {isIdle
    ? 'opacity-0 pointer-events-none'
    : 'opacity-100'}"
>
  <input
    type="range"
    min="0"
    max={duration || 0}
    bind:value={currentTime}
    class="w-full h-1 bg-zinc-600 rounded-lg appearance-none cursor-pointer accent-white"
  />

  <div class="flex items-center justify-between text-white text-sm mt-1">
    <div class="flex items-center gap-4">
      <button
        onclick={togglePlay}
        class="hover:text-zinc-300 transition-colors w-8 flex justify-center hover:cursor-pointer"
      >
        {#if paused}
          <Play size={22} fill="currentColor" />
        {:else}
          <Pause size={22} fill="currentColor" />
        {/if}
      </button>

      <div class="font-mono tabular-nums">
        {formatTime(currentTime)} / {formatTime(duration)}
      </div>
    </div>

    <div class="flex items-center gap-4">
      <div class="flex items-center gap-3 ml-2">
        <button
          onclick={toggleMute}
          class="text-white hover:text-primary transition-colors focus:outline-none hover:cursor-pointer"
          title={isMuted || volume === 0 ? "Unmute" : "Mute"}
        >
          {#if isMuted || volume === 0}
            <VolumeX size={20} class="drop-shadow-md" />
          {:else if volume < 0.5}
            <Volume1 size={20} class="drop-shadow-md" />
          {:else}
            <Volume2 size={20} class="drop-shadow-md" />
          {/if}
        </button>

        <div class="w-24 flex items-center">
          <input
            type="range"
            min="0"
            max="1"
            step="0.01"
            bind:value={volume}
            class="w-full h-1.5 bg-zinc-600/80 rounded-full appearance-none cursor-pointer accent-primary hover:accent-primary-hover focus:outline-none transition-all shadow-inner"
          />
        </div>
      </div>
      <button
        onclick={() => toggleSettings()}
        class="hover:text-zinc-300 transition-colors ml-2 hover:cursor-pointer"
      >
        <Settings size={20} />
      </button>
      <button
        onclick={() => onFullscreen?.()}
        class="hover:text-zinc-300 transition-colors ml-2 hover:cursor-pointer"
      >
        <Maximize size={20} />
      </button>
    </div>
  </div>
</div>
