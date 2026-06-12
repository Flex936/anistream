<script lang="ts">
  import { LoaderCircle, CircleCheck } from "@lucide/svelte";
  import { fade, fly } from "svelte/transition";

  let {
    hasScrobbled,
    isTrackingTimerActive,
  }: {
    hasScrobbled: boolean;
    isTrackingTimerActive: boolean;
  } = $props();

  let showSuccess = $state(false);

  $effect(() => {
    if (hasScrobbled) {
      showSuccess = true;
      const timer = setTimeout(() => {
        showSuccess = false;
      }, 3000);
      return () => clearTimeout(timer);
    } else {
      showSuccess = false;
    }
  });
</script>

<div class="absolute top-4 right-4 z-50 pointer-events-none">
  {#if showSuccess}
    <div
      in:fly={{ y: -10, duration: 300 }}
      out:fade={{ duration: 300 }}
      class="bg-green-500/90 text-white px-4 py-2 rounded-full text-sm font-bold shadow-lg flex items-center space-x-2"
    >
      <CircleCheck size={16} />
      <span>Saved to AniList</span>
    </div>
  {:else if isTrackingTimerActive}
    <div
      in:fly={{ y: -10, duration: 300 }}
      out:fade={{ duration: 300 }}
      class="bg-yellow-500/90 text-white px-4 py-2 rounded-full text-sm font-bold shadow-lg flex items-center space-x-2"
    >
      <LoaderCircle size={16} class="animate-spin" />
      <span>Tracking...</span>
    </div>
  {/if}
</div>
