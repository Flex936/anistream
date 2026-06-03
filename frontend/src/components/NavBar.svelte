<script lang="ts">
    import { createEventDispatcher, onMount } from "svelte";
    import {
        Search,
        Settings,
        Minus,
        Maximize2,
        Minimize2,
        X,
    } from "lucide-svelte";
    import {
        WindowMinimise,
        WindowIsMaximised,
        WindowUnmaximise,
        WindowMaximise,
        Quit,
    } from "../../wailsjs/runtime/runtime";

    export let searchQuery = "";
    const dispatch = createEventDispatcher();
    let isMaximised = false;

    onMount(async () => {
        isMaximised = await WindowIsMaximised();
    });

    function handleInput() {
        dispatch("search", searchQuery);
    }

    async function handleWindowMaximise() {
        const currentlyMaximised = await WindowIsMaximised();

        if (currentlyMaximised) {
            WindowUnmaximise();
            isMaximised = false;
        } else {
            WindowMaximise();
            isMaximised = true;
        }
    }
</script>

<nav
    style="--wails-draggable: drag;"
    class="sticky top-0 z-50 bg-slate-950/80 backdrop-blur-md border-b border-slate-800 px-6 py-4 flex items-center justify-between"
>
    <div class="flex items-center space-x-2 text-indigo-400">
        <h1 class="text-xl font-bold tracking-tight text-white">AniStream</h1>
    </div>

    <div class="flex-1 max-w-2xl px-8">
        <div class="relative group">
            <div
                class="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none text-slate-400 group-focus-within:text-indigo-400 transition-colors"
            >
                <Search size={20} />
            </div>
            <input
                style="--wails-draggable: no-drag;"
                type="text"
                bind:value={searchQuery}
                on:input={handleInput}
                placeholder="Search for anime by title..."
                class="w-full bg-slate-900 border border-slate-700 text-slate-200 text-sm rounded-full focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 block pl-11 p-2.5 transition-all shadow-inner outline-none"
            />
        </div>
    </div>
    <!-- Far Right Icons -->
    <div class="flex items-center space-x-4 text-slate-400">
        <button
            style="--wails-draggable: no-drag;"
            class="hover:text-white transition-colors"
        >
            <Settings size={20} />
        </button>

        <!-- Custom Window Controls -->
        <div class="flex items-center space-x-2 border-l border-slate-700 pl-4">
            <button
                style="--wails-draggable: no-drag;"
                on:click={WindowMinimise}
                class="hover:text-white transition-colors"
            >
                <Minus size={20} />
            </button>
            <button
                style="--wails-draggable: no-drag;"
                on:click={handleWindowMaximise}
                class="hover:text-yellow-500 transition-colors"
            >
                {#if isMaximised}
                    <Minimize2 size={20} />
                {:else}
                    <Maximize2 size={20} />
                {/if}
            </button>
            <button
                style="--wails-draggable: no-drag;"
                on:click={Quit}
                class="hover:text-red-400 transition-colors"
            >
                <X size={20} />
            </button>
        </div>
    </div>
</nav>
