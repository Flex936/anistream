<script lang="ts">
    import { createEventDispatcher } from "svelte";
    import { Search, Settings, Clapperboard } from "lucide-svelte";

    export let searchQuery = "";

    const dispatch = createEventDispatcher();

    function handleInput() {
        dispatch("search", searchQuery);
    }
</script>

<nav
    class="sticky top-0 z-50 bg-slate-950/80 backdrop-blur-md border-b border-slate-800 px-6 py-4 flex items-center justify-between"
>
    <div class="flex items-center space-x-2 text-indigo-400">
        <Clapperboard size={28} />
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
                type="text"
                bind:value={searchQuery}
                on:input={handleInput}
                placeholder="Search for anime by title..."
                class="w-full bg-slate-900 border border-slate-700 text-slate-200 text-sm rounded-full focus:ring-2 focus:ring-indigo-500 focus:border-indigo-500 block pl-11 p-2.5 transition-all shadow-inner outline-none"
            />
        </div>
    </div>

    <div
        class="flex items-center text-slate-400 hover:text-white cursor-pointer transition-colors"
    >
        <Settings size={24} />
    </div>
</nav>
