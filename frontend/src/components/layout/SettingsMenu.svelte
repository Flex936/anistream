<script lang="ts">
  import { onMount } from "svelte";
  import { X, Monitor, Zap, Cpu, Film, TriangleAlert } from "@lucide/svelte";
  import {
    GetResolution,
    UpdateResolution,
    GetEcchiFilter,
    UpdateEcchiFilter,
    GetTranscoder,
    UpdateTranscoder,
    GetAV1Enabled,
    UpdateAV1Enabled,
  } from "../../../wailsjs/go/main/App";
  import { WindowSetSize } from "../../../wailsjs/runtime/runtime";

  let { onClose }: { onClose?: () => void } = $props();

  let activeTab = $state("general");
  let isSaving = $state(false);
  let filterEcchi = $state(true);
  let selectedEncoder = $state("libx264");
  let enableAV1 = $state(false);

  const resolutions = [
    { label: "720p HD (1280 x 720)", w: 1280, h: 720 },
    { label: "900p HD+ (1600 x 900)", w: 1600, h: 900 },
    { label: "1080p Full HD (1920 x 1080)", w: 1920, h: 1080 },
    { label: "1440p QHD (2560 x 1440)", w: 2560, h: 1440 },
  ];

  const encoders = [
    {
      id: "libx264",
      name: "Software",
      desc: "Compatible with all.",
    },
    {
      id: "h264_nvenc",
      name: "NVENC",
      desc: "For NVIDIA cards.",
    },
    {
      id: "h264_amf",
      name: "AMF",
      desc: "For AMD graphics.",
    },
    {
      id: "h264_qsv",
      name: "QuickSync",
      desc: "For Intel graphics.",
    },
    {
      id: "h264_videotoolbox",
      name: "Apple Silicon",
      desc: "For M1/M2/M3 Mac users.",
    },
  ];

  let selectedRes = $state(resolutions[0]);

  onMount(async () => {
    try {
      const currentRes = await GetResolution();
      const match = resolutions.find(
        (r) => r.w === currentRes.width && r.h === currentRes.height,
      );
      if (match) selectedRes = match;

      filterEcchi = await GetEcchiFilter();
      selectedEncoder = await GetTranscoder();
      enableAV1 = await GetAV1Enabled();
    } catch (err) {
      console.error("Failed to fetch settings:", err);
    }
  });

  async function handleSave() {
    isSaving = true;
    try {
      await UpdateResolution(selectedRes.w, selectedRes.h);
      await UpdateEcchiFilter(filterEcchi);
      await UpdateTranscoder(selectedEncoder);
      await UpdateAV1Enabled(enableAV1);

      WindowSetSize(selectedRes.w, selectedRes.h);
      onClose?.();
    } catch (err) {
      console.error("Failed to save settings:", err);
      alert("Error saving settings");
    } finally {
      isSaving = false;
    }
  }
</script>

<div
  class="fixed inset-0 z-100 flex items-center justify-center bg-black/60 backdrop-blur-sm p-4"
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
        onclick={() => (activeTab = "general")}
      >
        <Monitor size={18} />
        <span class="font-medium">General</span>
      </button>

      <button
        class="flex items-center space-x-3 px-4 py-2 rounded-lg transition-colors {activeTab ===
        'playback'
          ? 'bg-primary/20 text-primary'
          : 'text-muted hover:bg-surface hover:text-main'}"
        onclick={() => (activeTab = "playback")}
      >
        <Film size={18} />
        <span class="font-medium">Playback</span>
      </button>
    </div>

    <div class="flex-1 flex flex-col relative min-h-[500px]">
      <button
        class="absolute top-4 right-4 p-2 text-muted hover:text-red-400 hover:bg-red-400/10 rounded-full transition-colors z-10"
        onclick={() => onClose?.()}
      >
        <X size={20} />
      </button>

      <div class="p-8 flex-1 overflow-y-auto">
        {#if activeTab === "general"}
          <div class="animate-in fade-in slide-in-from-right-4 duration-300">
            <h3 class="text-2xl font-bold text-main mb-6">General Settings</h3>

            <div class="space-y-6">
              <div class="space-y-3">
                <span
                  class="text-xs font-semibold text-muted uppercase tracking-wider"
                  >Startup Resolution</span
                >
                <div class="grid grid-cols-2 gap-3">
                  {#each resolutions as res}
                    <button
                      class="flex flex-col items-start p-3 rounded-xl border-2 transition-all duration-200 {selectedRes.label ===
                      res.label
                        ? 'border-primary bg-primary/10'
                        : 'border-border bg-base hover:border-gray-500'}"
                      onclick={() => (selectedRes = res)}
                    >
                      <span
                        class="font-bold text-sm {selectedRes.label ===
                        res.label
                          ? 'text-primary'
                          : 'text-gray-200'}">{res.label.split("(")[0]}</span
                      >
                      <span
                        class="text-[10px] {selectedRes.label === res.label
                          ? 'text-primary/80'
                          : 'text-gray-500'}">{res.w} x {res.h}</span
                      >
                    </button>
                  {/each}
                </div>
              </div>

              <div
                class="pt-6 border-t border-border flex items-center justify-between"
              >
                <div>
                  <span
                    class="text-sm font-semibold text-main uppercase tracking-wider block"
                    >Filter Ecchi Content</span
                  >
                  <span class="text-xs text-muted"
                    >Hide borderline NSFW shows.</span
                  >
                </div>
                <button
                  aria-label="Toggle Ecchi Filter"
                  class="relative inline-flex h-6 w-11 items-center rounded-full transition-colors {filterEcchi
                    ? 'bg-primary'
                    : 'bg-gray-600'}"
                  onclick={() => (filterEcchi = !filterEcchi)}
                >
                  <span
                    class="inline-block h-4 w-4 transform rounded-full bg-white transition-transform {filterEcchi
                      ? 'translate-x-6'
                      : 'translate-x-1'}"
                  ></span>
                </button>
              </div>
            </div>
          </div>
        {:else if activeTab === "playback"}
          <div class="animate-in fade-in slide-in-from-right-4 duration-300">
            <h3 class="text-2xl font-bold text-main mb-2">
              Hardware Acceleration
            </h3>
            <p class="text-sm text-muted mb-6">
              Using your GPU reduces buffer time and CPU load.
            </p>

            <div class="space-y-3">
              {#each encoders as enc}
                <button
                  class="w-full flex items-center p-4 rounded-xl border-2 transition-all duration-200 {selectedEncoder ===
                  enc.id
                    ? 'border-primary bg-primary/10'
                    : 'border-border bg-base hover:border-gray-500 text-left'}"
                  onclick={() => (selectedEncoder = enc.id)}
                >
                  <div
                    class="p-2 rounded-lg {selectedEncoder === enc.id
                      ? 'bg-primary text-white'
                      : 'bg-surface text-muted'} mr-4"
                  >
                    {#if enc.id === "libx264"}<Cpu size={20} />{:else}<Zap
                        size={20}
                      />{/if}
                  </div>
                  <div class="flex flex-col text-left">
                    <span
                      class="font-bold {selectedEncoder === enc.id
                        ? 'text-primary'
                        : 'text-main'}">{enc.name}</span
                    >
                    <span class="text-xs text-muted">{enc.desc}</span>
                  </div>
                </button>
              {/each}
            </div>
            <div class="pt-6 border-t border-border">
              <div class="flex items-start justify-between">
                <div class="flex flex-col max-w-[80%]">
                  <span
                    class="text-sm font-bold text-main flex items-center gap-2"
                  >
                    Enable AV1 Encoding
                    <span
                      class="px-1.5 py-0.5 rounded-md bg-amber-500/20 text-amber-500 text-[10px] uppercase font-bold tracking-wider"
                      >Experimental</span
                    >
                  </span>
                  <p class="text-xs text-muted mt-1 leading-relaxed">
                    Upgrades NVENC, AMF, or QuickSync to use the AV1 codec
                    instead of H.264.
                    <br />
                    <strong class="text-red-400">WARNING:</strong> This will only
                    work on RTX 40-series, RX 7000-series, or Intel Arc GPU (and
                    above).
                  </p>
                </div>

                <button
                  aria-label="Toggle AV1"
                  disabled={selectedEncoder === "libx264" ||
                    selectedEncoder === "h264_videotoolbox"}
                  class="relative mt-2 inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-primary disabled:opacity-30 disabled:cursor-not-allowed {enableAV1
                    ? 'bg-amber-500'
                    : 'bg-gray-600'}"
                  onclick={() => (enableAV1 = !enableAV1)}
                >
                  <span
                    class="inline-block h-4 w-4 transform rounded-full bg-white transition-transform {enableAV1
                      ? 'translate-x-6'
                      : 'translate-x-1'}"
                  ></span>
                </button>
              </div>

              {#if selectedEncoder === "libx264" || selectedEncoder === "h264_videotoolbox"}
                <p
                  class="text-[10px] text-amber-500/80 mt-2 flex items-center gap-1"
                >
                  <TriangleAlert size={12} /> Requires a dedicated GPU encoder to
                  be selected above.
                </p>
              {/if}
            </div>
          </div>
        {/if}
      </div>

      <div class="border-t border-border p-4 bg-base flex justify-end">
        <button
          onclick={handleSave}
          disabled={isSaving}
          class="bg-primary hover:bg-primary/90 text-white font-medium px-8 py-2 rounded-lg transition-colors shadow-lg disabled:opacity-50"
        >
          {isSaving ? "Saving..." : "Save Changes"}
        </button>
      </div>
    </div>
  </div>
</div>
