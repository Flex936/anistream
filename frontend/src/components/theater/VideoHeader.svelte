<script lang="ts">
  import { createEventDispatcher } from "svelte";
  import { ArrowLeft } from "lucide-svelte";

  export let playingEpisode: number;

  const dispatch = createEventDispatcher();
</script>

<div class="flex items-center justify-between">
  <div class="flex flex-col">
    <h3 class="text-xl font-semibold text-main flex items-center">
      Episode {playingEpisode}
    </h3>
  </div>

  <button
    on:click={() => dispatch("back")}
    class="flex items-center space-x-2 text-sm text-primary hover:text-primary-hover transition-colors group"
  >
    <ArrowLeft
      size={16}
      class="group-hover:-translate-x-1 transition-transform"
    />
    <span>Back to Release List</span>
  </button>
</div>
