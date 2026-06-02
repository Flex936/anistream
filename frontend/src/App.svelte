<script lang="ts">
  import { SearchAnime } from "../wailsjs/go/main/App";
  import type { main } from "../wailsjs/go/models";

  // State Variables
  let searchQuery = "";
  let isSearching = false;
  let searchResults: main.Anime[] = [];
  let searchTimeout: ReturnType<typeof setTimeout>;

  // The function that triggers the Go backend
  async function performSearch() {
    if (searchQuery.trim().length < 3) {
      searchResults = [];
      return;
    }

    isSearching = true;
    try {
      // Call the Go function directly!
      const results = await SearchAnime(searchQuery);
      searchResults = results || [];
    } catch (err) {
      console.error("Failed to search AniList:", err);
    } finally {
      isSearching = false;
    }
  }

  // Debounce the input so we don't spam the Go API on every keystroke
  function handleInput() {
    clearTimeout(searchTimeout);
    searchTimeout = setTimeout(() => {
      performSearch();
    }, 500); // Waits 500ms after the user stops typing
  }
</script>

<main class="min-h-screen flex flex-col">
  <nav
    class="sticky top-0 z-50 bg-slate-950/80 backdrop-blur-md border-b border-slate-800 px-6 py-4 flex items-center justify-between"
  >
    <div class="flex items-center space-x-2">
      <h1 class="text-xl font-bold tracking-tight text-white">AniStream</h1>
    </div>

    <div class="flex-1 max-w-2xl px-8">
      <div class="relative group">
        <div
          class="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none"
        >
          <svg
            class="h-5 w-5 text-slate-400 group-focus-within:text-indigo-400 transition-colors"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
            stroke="currentColor"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0z"
            />
          </svg>
        </div>
        <input
          type="text"
          bind:value={searchQuery}
          on:input={handleInput}
          placeholder="Search for anime by title..."
          class="..."
        />
      </div>
    </div>

    <div
      class="flex items-center text-slate-400 hover:text-white cursor-pointer transition-colors"
    >
      <svg
        class="w-6 h-6"
        fill="none"
        stroke="currentColor"
        viewBox="0 0 24 24"
        xmlns="http://www.w3.org/2000/svg"
        ><path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z"
        ></path><path
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="2"
          d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
        ></path></svg
      >
    </div>
  </nav>

  <div class="mb-8 flex items-center justify-between">
    <div>
      <h2 class="text-2xl font-semibold text-slate-100">
        {#if searchQuery}
          Results for "{searchQuery}"
        {:else}
          Discover Anime
        {/if}
      </h2>
      <p class="text-slate-400 mt-1 text-sm">
        Type in the search bar above to query AniList.
      </p>
    </div>

    {#if isSearching}
      <div
        class="w-6 h-6 border-2 border-indigo-500 border-t-transparent rounded-full animate-spin"
      ></div>
    {/if}
  </div>

  <div
    class="grid grid-cols-2 md:grid-cols-4 lg:grid-cols-5 xl:grid-cols-6 gap-6"
  >
    {#each searchResults as anime}
      <article
        class="group relative flex flex-col cursor-pointer transition-all duration-300 hover:scale-[1.02]"
      >
        <div
          class="relative w-full aspect-[2/3] rounded-xl overflow-hidden shadow-lg border border-slate-800 bg-slate-900 group-hover:border-indigo-500/50 transition-colors"
        >
          <img
            src={anime.coverImage.large}
            alt={anime.title.romaji || anime.title.english}
            class="w-full h-full object-cover"
          />

          <div
            class="absolute top-2 left-2 bg-black/70 backdrop-blur-sm px-2 py-1 rounded text-xs font-semibold text-white border shadow-md
              {anime.status === 'RELEASING'
              ? 'text-green-400 border-green-400/20'
              : 'text-slate-300 border-slate-500/20'}"
          >
            {anime.status}
          </div>

          <div
            class="absolute inset-0 bg-black/40 opacity-0 group-hover:opacity-100 flex items-center justify-center transition-opacity"
          >
            <div
              class="bg-indigo-600 rounded-full p-3 shadow-xl transform translate-y-4 group-hover:translate-y-0 transition-transform"
            >
              <svg
                class="w-6 h-6 text-white ml-1"
                fill="currentColor"
                viewBox="0 0 20 20"
                ><path
                  fill-rule="evenodd"
                  d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z"
                  clip-rule="evenodd"
                ></path></svg
              >
            </div>
          </div>
        </div>

        <div class="mt-3 flex flex-col">
          <h3
            class="font-medium text-sm text-slate-200 line-clamp-2 leading-snug group-hover:text-indigo-400 transition-colors"
          >
            {anime.title.romaji || anime.title.english}
          </h3>
          <span class="text-xs text-slate-500 mt-1"
            >{anime.episodes || "?"} Episodes</span
          >
        </div>
      </article>
    {/each}
  </div>
</main>
