<script lang="ts">
  import { LoaderCircle, CircleCheck } from "@lucide/svelte";

  let {
    hasScrobbled,
    isTrackingTimerActive,
  }: {
    hasScrobbled: boolean;
    isTrackingTimerActive: boolean;
  } = $props();
</script>

<div class="absolute top-4 right-4 z-50 pointer-events-none">
  {#if hasScrobbled}
    <div
      class="bg-green-500/90 text-white px-4 py-2 rounded-full text-sm font-bold shadow-lg transition-all duration-300 flex items-center space-x-2"
    >
      <CircleCheck size={16} />
      <span>Saved to AniList</span>
    </div>
  {:else if isTrackingTimerActive}
    <div
      class="bg-yellow-500/90 text-white px-4 py-2 rounded-full text-sm font-bold shadow-lg transition-all duration-300 flex items-center space-x-2"
    >
      <LoaderCircle size={16} class="animate-spin" />
      <span>Tracking...</span>
    </div>
  {/if}
</div>
