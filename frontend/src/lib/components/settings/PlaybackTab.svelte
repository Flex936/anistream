<script lang="ts">
  import { Zap, Cpu, TriangleAlert } from "@lucide/svelte";
  import ToggleSwitch from "$lib/components/ui/ToggleSwitch.svelte";

  let {
    selectedEncoder = $bindable(),
    encoders,
    enableAV1 = $bindable(),
    enableOpus = $bindable(),
  } = $props();
</script>

<div class="animate-in fade-in slide-in-from-right-4 duration-300 pb-4">
  <h3 class="text-2xl font-bold text-main mb-2">Hardware Acceleration</h3>
  <p class="text-sm text-muted mb-6">
    Using your GPU reduces buffer time and CPU load.
  </p>

  <div class="space-y-3">
    {#each encoders as enc}
      <button
        class="w-full flex items-center p-4 rounded-xl border-2 transition-all duration-200
               {selectedEncoder === enc.id
          ? 'border-primary bg-primary/10'
          : 'border-border bg-base hover:border-gray-500 text-left'}"
        onclick={() => (selectedEncoder = enc.id)}
      >
        <div
          class="p-2 rounded-lg mr-4
                 {selectedEncoder === enc.id
            ? 'bg-primary text-white'
            : 'bg-surface text-muted'}"
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

  <!-- AV1 toggle -->
  <div class="pt-6 border-t border-border mt-6">
    <div class="flex items-start justify-between">
      <div class="flex flex-col max-w-[80%]">
        <span class="text-sm font-bold text-main">Enable AV1 Encoding</span>
        <p class="text-xs text-muted mt-1 leading-relaxed">
          Upgrades NVENC, AMF, or QuickSync to AV1 instead of H.264.<br />
          <strong class="text-red-400">WARNING:</strong> Requires RTX 40-series, RX
          7000-series, or Intel Arc (and above).
        </p>
      </div>
      <ToggleSwitch
        bind:checked={enableAV1}
        disabled={selectedEncoder === "libx264" ||
          selectedEncoder === "h264_videotoolbox"}
      />
    </div>
    {#if selectedEncoder === "libx264" || selectedEncoder === "h264_videotoolbox"}
      <p class="text-[10px] text-amber-500/80 mt-2 flex items-center gap-1">
        <TriangleAlert size={12} /> Requires a dedicated GPU encoder to be selected
        above.
      </p>
    {/if}
  </div>

  <!-- Opus toggle -->
  <div class="pt-6 border-t border-border mt-6">
    <div class="flex items-start justify-between">
      <div class="flex flex-col max-w-[80%]">
        <span class="text-sm font-bold text-main">Enable Opus Encoding</span>
        <p class="text-xs text-muted mt-1 leading-relaxed">
          Better audio quality at lower bitrates vs standard AAC.<br />
          <strong class="text-red-400">WARNING:</strong> Do not enable on macOS —
          Apple's HLS engine doesn't support Opus.
        </p>
      </div>
      <ToggleSwitch bind:checked={enableOpus} />
    </div>
  </div>
</div>
