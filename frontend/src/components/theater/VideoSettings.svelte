<script lang="ts">
  import { Captions, AudioLines, ArrowLeft } from "@lucide/svelte";
  let {
    SettingsOpen = $bindable(),
    animeData,
    SelectedSub,
    SelectedAudio,
    OnTrackChange,
  } = $props();

  let closeTimeout: number;
  let SettingsView = $state<"main" | "subs" | "audio">("main");

  function handleMouseLeave() {
    closeTimeout = setTimeout(() => {
      SettingsOpen = false;
      setTimeout(() => {
        if (!SettingsOpen) SettingsView = "main";
      }, 300);
    }, 300);
  }

  function handleMouseEnter() {
    clearTimeout(closeTimeout);
  }
</script>

<div
  class="absolute bottom-16 right-4 z-50 w-64 h-auto bg-black/80 border-zinc-800/80 border-2 rounded-lg p-5 text-white shadow-xl backdrop-blur-sm transition-all duration-300 ease-in-out
        {SettingsOpen
    ? 'opacity-100 translate-y-0 pointer-events-auto'
    : 'opacity-0 translate-y-2 pointer-events-none delay-200'}"
  onmouseleave={handleMouseLeave}
  onmouseenter={handleMouseEnter}
  role="dialog"
  aria-label="Player Settings"
  tabindex="0"
>
  {#if SettingsView === "main"}
    <div
      class="text-sm mb-2 p-2 hover:cursor-pointer rounded-md hover:bg-white/10 flex row"
      onclick={() => (SettingsView = "subs")}
      role="button"
      aria-label="Subtitle Change"
      tabindex="0"
      onkeydown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          SettingsView = "subs";
        }
      }}
    >
      <span class="mr-1"><Captions size={20} /></span><span>Subtitles</span
      ><span class="absolute right-7 text-gray-700 truncate"
        >{#if SelectedSub}{SelectedSub?.lang} ({SelectedSub?.title}){:else}
          None
        {/if}</span
      >
    </div>
    <div
      class="text-sm p-2 hover:cursor-pointer rounded-md hover:bg-white/10 flex row"
      onclick={() => (SettingsView = "audio")}
      role="button"
      aria-label="Audio Change"
      tabindex="0"
      onkeydown={(e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          SettingsView = "audio";
        }
      }}
    >
      <span class="mr-1"><AudioLines size={20} /></span><span>Audio Tracks</span
      ><span class="absolute right-7 text-gray-700"
        >{#if SelectedAudio}{SelectedAudio?.lang}{:else}
          ???
        {/if}</span
      >
    </div>
  {:else if SettingsView === "subs"}
    <button
      class="text-sm mb-2 p-2 hover:cursor-pointer rounded-md hover:bg-white/10 flex row relative top-0 left-0 text-gray-500"
      onclick={() => (SettingsView = "main")}
      aria-label="Subtitle Change"
      tabindex="0"
      ><ArrowLeft size={20} />Back
    </button>

    <div class="max-h-48 overflow-y-auto flex flex-col gap-1 custom-scrollbar">
      <button
        class="text-sm mb-2 p-2 hover:cursor-pointer rounded-md hover:bg-white/10 w-full text-left"
        onclick={() =>
          OnTrackChange(
            "no",
            SelectedAudio ? SelectedAudio.id.toString() : "auto",
          )}
      >
        Disable Subtitles
      </button>
      {#each animeData?.subtitles ?? [] as subtitle}
        <button
          class="text-sm mb-2 p-2 hover:cursor-pointer rounded-md hover:bg-white/10 w-full text-left {subtitle.selected
            ? 'text-sky-400 font-bold'
            : ''}"
          onclick={() =>
            OnTrackChange(
              subtitle.id.toString(),
              SelectedAudio ? SelectedAudio.id.toString() : "auto",
            )}
        >
          {subtitle.lang} ({subtitle.title})
        </button>
      {/each}
    </div>
  {:else if SettingsView === "audio"}
    <button
      class="text-sm m-2 p-2 hover:cursor-pointer rounded-md hover:bg-white/10 flex row absolute top-0 left-0 text-gray-500"
      onclick={() => (SettingsView = "main")}
      aria-label="Audio Change"
      tabindex="0"
      ><ArrowLeft size={20} />Back
    </button>
    <div
      class="max-h-48 overflow-y-auto flex flex-col gap-1 custom-scrollbar pt-8"
    >
      {#each animeData?.audio_tracks ?? [] as audio}
        <button
          class="text-sm mb-2 p-2 hover:cursor-pointer rounded-md hover:bg-white/10 w-full text-left {audio.selected
            ? 'text-sky-400 font-bold'
            : ''}"
          onclick={() =>
            OnTrackChange(
              SelectedSub ? SelectedSub.id.toString() : "auto",
              audio.id.toString(),
            )}
        >
          {audio.lang}
        </button>
      {/each}
    </div>
  {/if}
</div>

<style>
  .custom-scrollbar::-webkit-scrollbar {
    width: 6px;
  }
  .custom-scrollbar::-webkit-scrollbar-track {
    background: transparent;
  }
  .custom-scrollbar::-webkit-scrollbar-thumb {
    background-color: #3f3f46;
    border-radius: 10px;
  }
  .custom-scrollbar::-webkit-scrollbar-thumb:hover {
    background-color: #52525b;
  }
</style>
