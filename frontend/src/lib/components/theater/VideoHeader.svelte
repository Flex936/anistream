<script lang="ts">
  import { ArrowLeft } from "@lucide/svelte";

  let {
    playingEpisode,
    onBack,
  }: { playingEpisode: number; onBack?: () => void } = $props();
</script>

<div class="flex items-center justify-between">
  <div class="flex flex-col">
    <h3 class="text-xl font-semibold text-main flex items-center">
      Episode {playingEpisode}
    </h3>
  </div>
  <button
    onclick={() => onBack?.()}
    class="flex items-center space-x-2 text-sm text-primary hover:text-primary-hover transition-colors group"
  >
    <ArrowLeft
      size={16}
      class="group-hover:-translate-x-1 transition-transform"
    />
    <span>Back to Release List</span>
  </button>
</div>
