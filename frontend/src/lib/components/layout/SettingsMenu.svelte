<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { X, Monitor, Film, ImageUp } from "@lucide/svelte"; // Note: Used ImageUp as ImageUpscale doesn't exist in standard Lucide
  import {
    GetResolution,
    UpdateResolution,
    GetEcchiFilter,
    UpdateEcchiFilter,
    GetInternalPlayback,
    UpdateInternalPlayback,
    GetUpscaleMethod,
    UpdateUpscaleMethod,
    GetUpscaleResolution,
    UpdateUpscaleResolution,
    GetFolder,
    OpenDirectoryDialog,
    UpdateDownloadFolder,
  } from "$wails/go/main/App";
  import { WindowSetSize } from "$wails/runtime/runtime";

  import GeneralTab from "$lib/components/settings/GeneralTab.svelte";
  import PlaybackTab from "$lib/components/settings/PlaybackTab.svelte";
  import UpscaleTab from "$lib/components/settings/UpscaleTab.svelte";

  let { onClose }: { onClose?: () => void } = $props();

  let activeTab = $state("general");
  let isSaving = $state(false);
  let filterEcchi = $state(true);
  let internalPlayback = $state(false);
  let upscalingMethod = $state("");
  let chosenPath = $state("");

  const resolutions = [
    { label: "720p HD (1280 x 720)", w: 1280, h: 720 },
    { label: "900p HD+ (1600 x 900)", w: 1600, h: 900 },
    { label: "1080p Full HD (1920 x 1080)", w: 1920, h: 1080 },
    { label: "1440p QHD (2560 x 1440)", w: 2560, h: 1440 },
  ];



  const upscalers = [
    { id: "", name: "None", desc: "Disable upscaling" },
    {
      id: "lanczos",
      name: "Lanczos",
      desc: "Sharp, traditional 2D grid scaling.",
    },
    {
      id: "ewa_lanczos",
      name: "EWA Lanczos",
      desc: "Circular, natural, high-performance reconstruction.",
    },
    {
      id: "ewa_lanczossharp",
      name: "EWA Lanczos Sharp",
      desc: "Mathematically tweaked EWA for maximum crispness.",
    },
  ];

  const targetResolutions = [
    { id: "0", label: "1080p Full HD (1920 x 1080)", w: 1920, h: 1080 },
    { id: "1", label: "1440p QHD (2560 x 1440)", w: 2560, h: 1440 },
    { id: "2", label: "2160p UHD (3840 x 2160)", w: 3840, h: 2160 },
  ];

  let selectedRes = $state(resolutions[0]);
  let upscalingResolution: any = $state({ ...targetResolutions[0] });

  onMount(async () => {
    document.body.style.overflow = "hidden";
    try {
      const currentRes = await GetResolution();
      const match = resolutions.find(
        (r) => r.w === currentRes.width && r.h === currentRes.height,
      );
      if (match) selectedRes = match;

      filterEcchi = await GetEcchiFilter();
      internalPlayback = await GetInternalPlayback();
      chosenPath = await GetFolder();
      upscalingMethod = await GetUpscaleMethod();
      const savedUpscaleRes = await GetUpscaleResolution();
      const matchUpscale = targetResolutions.find(
        (r) => r.w === savedUpscaleRes.width && r.h === savedUpscaleRes.height,
      );
      if (matchUpscale) {
        upscalingResolution = { ...matchUpscale };
      } else {
        upscalingResolution = {
          id: "4",
          w: savedUpscaleRes.width,
          h: savedUpscaleRes.height,
        };
      }
    } catch (err) {
      console.error("Failed to fetch settings:", err);
    }
  });

  onDestroy(() => {
    document.body.style.overflow = "";
  });

  async function handleSave() {
    isSaving = true;
    try {
      await UpdateResolution(selectedRes.w, selectedRes.h);
      await UpdateEcchiFilter(filterEcchi);
      await UpdateInternalPlayback(internalPlayback);
      await UpdateUpscaleMethod(upscalingMethod);
      await UpdateUpscaleResolution({
        width: upscalingResolution?.w,
        height: upscalingResolution?.h,
      });
      await UpdateDownloadFolder(chosenPath);

      WindowSetSize(selectedRes.w, selectedRes.h);
      onClose?.();
    } catch (err) {
      console.error("Failed to save settings:", err);
      alert("Error saving settings");
    } finally {
      isSaving = false;
    }
  }

  async function changeDownloadFolder() {
    try {
      // Call the exposed Go method
      const path = await OpenDirectoryDialog();
      if (path) {
        chosenPath = path;
      }
    } catch (err) {
      console.error("Failed to select directory:", err);
    }
  }
</script>

<div
  class="fixed inset-0 z-100 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4"
>
  <div
    class="w-full max-w-3xl bg-surface border border-border rounded-xl shadow-2xl
           flex overflow-hidden animate-in fade-in zoom-in-95 duration-200 h-[600px]"
  >
    <div
      class="w-64 bg-base border-r border-border p-4 flex flex-col space-y-2"
    >
      <h2 class="text-xl font-bold text-main px-4 py-2 mb-4">Settings</h2>

      <button
        class="flex items-center space-x-3 px-4 py-2 rounded-lg transition-colors
               {activeTab === 'general'
          ? 'bg-primary/20 text-primary'
          : 'text-muted hover:bg-surface hover:text-main'}"
        onclick={() => (activeTab = "general")}
      >
        <Monitor size={18} />
        <span class="font-medium">General</span>
      </button>

      <button
        class="flex items-center space-x-3 px-4 py-2 rounded-lg transition-colors
               {activeTab === 'playback'
          ? 'bg-primary/20 text-primary'
          : 'text-muted hover:bg-surface hover:text-main'}"
        onclick={() => (activeTab = "playback")}
      >
        <Film size={18} />
        <span class="font-medium">Playback</span>
      </button>

      <button
        class="flex items-center space-x-3 px-4 py-2 rounded-lg transition-colors
               {activeTab === 'upscale'
          ? 'bg-primary/20 text-primary'
          : 'text-muted hover:bg-surface hover:text-main'}"
        onclick={() => (activeTab = "upscale")}
      >
        <ImageUp size={18} />
        <span class="font-medium">Upscale</span>
      </button>
    </div>

    <div class="flex-1 flex flex-col relative h-full">
      <button
        class="absolute top-4 right-4 p-2 text-muted hover:text-red-400 hover:bg-red-400/10
               rounded-full transition-colors z-10"
        onclick={() => onClose?.()}
      >
        <X size={20} />
      </button>

      <div class="p-8 flex-1 overflow-y-auto custom-scrollbar">
        {#if activeTab === "general"}
          <GeneralTab
            bind:selectedRes
            {resolutions}
            bind:filterEcchi
            bind:chosenPath
            {changeDownloadFolder}
          />
        {:else if activeTab === "playback"}
          <PlaybackTab
            bind:internalPlayback
          />
        {:else if activeTab === "upscale"}
          <UpscaleTab
            bind:upscalingMethod
            bind:upscalingResolution
            {upscalers}
            {targetResolutions}
          />
        {/if}
      </div>

      <div class="border-t border-border p-4 bg-base flex justify-end shrink-0">
        <button
          onclick={handleSave}
          disabled={isSaving}
          class="bg-primary hover:bg-primary/90 text-white font-medium px-8 py-2 rounded-lg
                 transition-colors shadow-lg disabled:opacity-50"
        >
          {isSaving ? "Saving..." : "Save Changes"}
        </button>
      </div>
    </div>
  </div>
</div>
