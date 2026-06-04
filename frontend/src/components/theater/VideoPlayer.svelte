<script lang="ts">
    import { createEventDispatcher } from "svelte";

    export let streamUrl: string;
    export let playingEpisode: number;

    const dispatch = createEventDispatcher();
</script>

<div class="flex flex-col space-y-4 w-full">
    <div class="flex items-center justify-between">
        <h3 class="text-xl font-semibold text-slate-200 flex items-center">
            Episode {playingEpisode}
        </h3>
        <button
            on:click={() => dispatch("back")}
            class="text-sm text-indigo-400 hover:text-indigo-300 transition-colors"
        >
            &larr; Back to Release List
        </button>
    </div>
    <div
        class="w-full bg-black rounded-xl overflow-hidden shadow-2xl border border-slate-800 aspect-video animate-in fade-in zoom-in-95"
    >
        <video src={streamUrl} controls autoplay class="w-full h-full">
            <track kind="captions" srclang="en" label="English" />
        </video>
    </div>
</div>
