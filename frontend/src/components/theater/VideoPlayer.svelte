<script lang="ts">
    import { createEventDispatcher } from "svelte";
    import { ArrowLeft } from "lucide-svelte";

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
            class="flex items-center space-x-2 text-sm text-primary hover:text-primary-hover transition-colors"
        >
            <ArrowLeft size={16} />
            <span>Back to Release List</span>
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
