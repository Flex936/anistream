<script lang="ts">
  import { createEventDispatcher, onMount } from "svelte";
  import { X, Monitor, HardDrive } from "lucide-svelte";
  import {
    GetResolution,
    UpdateResolution,
  } from "../../../wailsjs/go/main/App";
  import { WindowSetSize } from "../../../wailsjs/runtime/runtime";

  const dispatch = createEventDispatcher();

  // State
  let activeTab = "general";
  let isSaving = false;

  // Available Resolutions
  const resolutions = [
    { label: "720p HD (1280 x 720)", w: 1280, h: 720 },
    { label: "900p HD+ (1600 x 900)", w: 1600, h: 900 },
    { label: "1080p Full HD (1920 x 1080)", w: 1920, h: 1080 },
    { label: "1440p QHD (2560 x 1440)", w: 2560, h: 1440 },
  ];

  // Bind the currently selected option
  let selectedRes = resolutions[0];

  onMount(async () => {
    try {
      const currentRes = await GetResolution();

      const match = resolutions.find(
        (r) => r.w === currentRes.width && r.h === currentRes.height,
      );
      if (match) selectedRes = match;
    } catch (err) {
      console.error("Failed to fetch resolution:", err);
    }
  });

  async function handleSave() {
    isSaving = true;
    try {
      await UpdateResolution(selectedRes.w, selectedRes.h);
      WindowSetSize(selectedRes.w, selectedRes.h);
      dispatch("close");
    } catch (err) {
      console.error("Failed to save settings:", err);
      alert("Error saving settings");
    } finally {
      isSaving = false;
    }
  }
</script>

<div
  class="fixed inset-0 z-[100] flex items-center justify-center bg-black/60 backdrop-blur-sm p-4"
>
  <div
    class="w-full max-w-3xl bg-surface border border-border rounded-xl shadow-2xl flex overflow-hidden animate-in fade-in zoom-in-95 duration-200"
  >
    <div
      class="w-64 bg-base border-r border-border p-4 flex flex-col space-y-2"
    >
      <h2 class="text-xl font-bold text-main px-4 py-2 mb-4">Settings</h2>

      <button
        class="flex items-center space-x-3 px-4 py-2 rounded-lg transition-colors {activeTab ===
        'general'
          ? 'bg-primary/20 text-primary'
          : 'text-muted hover:bg-surface hover:text-main'}"
        on:click={() => (activeTab = "general")}
      >
        <Monitor size={18} />
        <span class="font-medium">General</span>
      </button>

      <button
        class="flex items-center space-x-3 px-4 py-2 rounded-lg text-muted hover:bg-surface hover:text-main transition-colors"
        on:click={() => (activeTab = "downloads")}
      >
        <HardDrive size={18} />
        <span class="font-medium">Downloads</span>
      </button>
    </div>

    <div class="flex-1 flex flex-col relative min-h-[400px]">
      <button
        class="absolute top-4 right-4 p-2 text-muted hover:text-red-400 hover:bg-red-400/10 rounded-full transition-colors"
        on:click={() => dispatch("close")}
      >
        <X size={20} />
      </button>

      <div class="p-8 flex-1">
        {#if activeTab === "general"}
          <div class="animate-in fade-in slide-in-from-right-4 duration-300">
            <h3 class="text-2xl font-bold text-main mb-6">General Settings</h3>

            <div class="space-y-4 max-w-md">
              <label class="flex flex-col space-y-2">
                <span
                  class="text-sm font-semibold text-muted uppercase tracking-wider"
                  >Startup Resolution</span
                >
                <select
                  bind:value={selectedRes}
                  class="bg-base border border-border rounded-lg p-3 text-main focus:ring-2 focus:ring-primary focus:border-primary outline-none transition-all shadow-inner"
                >
                  {#each resolutions as res}
                    <option value={res}>{res.label}</option>
                  {/each}
                </select>
                <p class="text-xs text-muted pt-1">
                  This will be the default window size every time you open
                  AniStream.
                </p>
              </label>
            </div>
          </div>
        {:else if activeTab === "downloads"}
          <div class="animate-in fade-in slide-in-from-right-4 duration-300">
            <h3 class="text-2xl font-bold text-main mb-6">Downloads</h3>
            <p class="text-muted">Coming soon...</p>
          </div>
        {/if}
      </div>

      <div class="border-t border-border p-4 bg-base flex justify-end">
        <button
          on:click={handleSave}
          disabled={isSaving}
          class="bg-primary hover:bg-primary-hover text-white font-medium px-6 py-2 rounded-lg transition-colors shadow-md disabled:opacity-50"
        >
          {isSaving ? "Saving..." : "Save Changes"}
        </button>
      </div>
    </div>
  </div>
</div>
