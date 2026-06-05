<script lang="ts">
    import { createEventDispatcher } from "svelte";
    // Assuming these are your Wails runtime bindings
    import { EventsEmit } from "../../../wailsjs/runtime/runtime";

    export let streamUrl: string;
    export let playingEpisode: number;

    let videoElement: HTMLVideoElement;
    let isPaused = true;
    let currentTime = 0;
    let duration = 1389; // 23 minutes in seconds (you can pass this from Go metadata)

    function togglePlay() {
        if (!videoElement) return;
        if (videoElement.paused) {
            videoElement.play();
            isPaused = false;
        } else {
            videoElement.pause();
            isPaused = true;
        }
    }

    // Server-side Seeking: Tell Go to restart the MPV process at a specific second
    function handleScrub(e: Event) {
        const targetTime = parseFloat((e.target as HTMLInputElement).value);
        currentTime = targetTime;
        // Emit a Wails event that your backend listens to
        EventsEmit("player:seek", targetTime);
    }

    function formatTime(secs: number) {
        const m = Math.floor(secs / 60);
        const s = Math.floor(secs % 60);
        return `${m}:${s < 10 ? "0" : ""}${s}`;
    }
</script>

<div
    class="relative group w-full aspect-video bg-black rounded-xl overflow-hidden border border-zinc-800 shadow-2xl"
>
    <video
        bind:this={videoElement}
        src={streamUrl}
        autoplay
        class="w-full h-full object-contain"
        on:timeupdate={() => {
            if (!videoElement.paused) currentTime += 0.25;
        }}
    />

    <div
        class="absolute inset-0 bg-gradient-to-t from-black/80 via-transparent to-transparent opacity-0 group-hover:opacity-100 transition-opacity duration-300 flex flex-col justify-end p-4 space-y-3"
    >
        <div class="flex items-center space-x-2 w-full">
            <span class="text-xs text-zinc-400 font-mono"
                >{formatTime(currentTime)}</span
            >
            <input
                type="range"
                min="0"
                max={duration}
                value={currentTime}
                on:change={handleScrub}
                class="w-full h-1 bg-zinc-600 rounded-lg appearance-none cursor-pointer accent-primary"
            />
            <span class="text-xs text-zinc-400 font-mono"
                >{formatTime(duration)}</span
            >
        </div>

        <div class="flex items-center justify-between">
            <div class="flex items-center space-x-4">
                <button
                    on:click={togglePlay}
                    class="text-white hover:text-primary transition-colors text-sm font-semibold"
                >
                    {#if isPaused}
                        Play
                    {:else}
                        Pause
                    {/if}
                </button>
                <span class="text-sm text-zinc-300"
                    >Episode {playingEpisode}</span
                >
            </div>
        </div>
    </div>
</div>
