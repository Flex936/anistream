<script lang="ts">
    export let streamUrl: string;
    export let playingEpisode: number;
    import { onMount, onDestroy } from "svelte";
    import Hls from "hls.js";
    let videoElement;
    let hlsInstance;

    function initPlayer() {
        if (!streamUrl || !videoElement) return;

        // Reset player state if changing paths or instances
        if (hlsInstance) {
            hlsInstance.destroy();
        }

        // Check if the browser natively supports HLS (Safari/iOS default)
        if (videoElement.canPlayType("application/vnd.apple.mpegurl")) {
            videoElement.src = streamUrl;
        }
        // Use hls.js for all engines lacking native layout parsing (Chrome, Firefox, Electron/Wails)
        else if (Hls.isSupported()) {
            hlsInstance = new Hls({
                maxBufferLength: 10, // Max window chunk memory size (keeps disk-read footprint small)
                liveSyncDurationCount: 3, // Start playing after 3 chunks are written (~6 seconds)
            });

            hlsInstance.loadSource(streamUrl);
            hlsInstance.attachMedia(videoElement);

            hlsInstance.on(Hls.Events.MANIFEST_PARSED, () => {
                videoElement.play().catch((err) => {
                    console.log(
                        "Autoplay blocked, waiting for user interactions:",
                        err,
                    );
                });
            });

            hlsInstance.on(Hls.Events.ERROR, function (event, data) {
                if (data.fatal) {
                    switch (data.type) {
                        case Hls.ErrorTypes.NETWORK_ERROR:
                            console.log(
                                "HLS Network issue encountered, attempting reconnect...",
                            );
                            hlsInstance.startLoad();
                            break;
                        case Hls.ErrorTypes.MEDIA_ERROR:
                            console.log(
                                "HLS Media recovery processing triggered...",
                            );
                            hlsInstance.recoverMediaError();
                            break;
                        default:
                            initPlayer();
                            break;
                    }
                }
            });
        }
    }

    // Trigger video load hook on lifecycle mounting or route updates
    $: if (streamUrl && videoElement) {
        initPlayer();
    }

    onDestroy(() => {
        if (hlsInstance) {
            hlsInstance.destroy();
        }
    });
</script>

<div
    class="relative group w-full aspect-video bg-black rounded-xl overflow-hidden border border-zinc-800 shadow-2xl"
>
    <video
        bind:this={videoElement}
        controls
        preload="none"
        crossorigin="anonymous"
        class="w-full h-full object-contain"
    >
        <track kind="captions" />
    </video>
</div>
