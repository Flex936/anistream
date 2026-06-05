<script lang="ts">
    import { createEventDispatcher } from "svelte";

    export let streamUrl: string;
    export let playingEpisode: number;

    const dispatch = createEventDispatcher();
</script>

<div class="flex flex-col space-y-4 w-full">
    <div class="flex items-center justify-between">
        <h3 class="text-xl font-semibold text-main flex items-center">
            Episode {playingEpisode}
        </h3>

        <button
            on:click={() => dispatch("back")}
            class="text-sm text-primary hover:text-primary-hover transition-colors"
        >
            &larr; Back to Release List
        </button>
    </div>

    <div
        class="w-full bg-black rounded-xl shadow-2xl border border-border aspect-video animate-in fade-in"
    >
        <video src={streamUrl} controls autoplay class="w-full h-full">
            <track kind="captions" srclang="en" label="English" />
        </video>
    </div>
</div>
