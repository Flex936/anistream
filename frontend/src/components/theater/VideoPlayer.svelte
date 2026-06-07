<script lang="ts">
  import { createEventDispatcher, onMount, onDestroy } from "svelte";
  import {
    GetAnimeProgress,
    UpdateAnimeProgress,
  } from "../../../wailsjs/go/main/App";

  export let streamUrl: string;
  export let playingEpisode: number;
  export let animeId: number;

  const dispatch = createEventDispatcher();

  let currentProgress = 0;
  let hasScrobbled = false;
  let isTrackingTimerActive = false;
  let trackingTimeout: ReturnType<typeof setTimeout>;

  let currentTime = 0;
  let duration = 0;

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
    // Set the flag SYNCHRONOUSLY before yielding to the event loop.
    // forceScrobbleIfEligible can be called twice in the same microtask
    // (handleBack → onDestroy), so we must guard with a sync flag, not
    // one that is only set after the await resolves.
    hasScrobbled = true;
    isTrackingTimerActive = false;
    try {
      await UpdateAnimeProgress(animeId, playingEpisode);
    } catch (err) {
      console.error("Failed to scrobble to AniList", err);
      hasScrobbled = false; // roll back so the next eligible moment can retry
    }
  }

  function handleBack() {
    forceScrobbleIfEligible();
    dispatch("back");
  }

  onDestroy(() => {
    forceScrobbleIfEligible();
  });

  function forceScrobbleIfEligible() {
    clearTimeout(trackingTimeout);
    if (!hasScrobbled && duration > 0 && playingEpisode > currentProgress) {
      if (currentTime / duration >= 0.9) {
        triggerAniListUpdate();
      }
    }
  }
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
    class="relative w-full bg-black rounded-xl shadow-2xl border border-border aspect-video overflow-hidden"
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
      src={streamUrl}
      controls
      autoplay
      bind:currentTime
      bind:duration
      class="w-full h-full linux-fullscreen-fix"
    >
      <track kind="captions" srclang="en" label="English" />
    </video>
  </div>
</div>
