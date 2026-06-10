<script lang="ts">
  import { Zap, Cpu, TriangleAlert } from "@lucide/svelte";
  import ToggleSwitch from "./ToggleSwitch.svelte";

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

  <div class="pt-6 border-t border-border mt-6">
    <div class="flex items-start justify-between">
      <div class="flex flex-col max-w-[80%]">
        <span class="text-sm font-bold text-main flex items-center gap-2">
          Enable AV1 Encoding
        </span>
        <p class="text-xs text-muted mt-1 leading-relaxed">
          Upgrades NVENC, AMF, or QuickSync to use the AV1 codec instead of
          H.264.<br />
          <strong class="text-red-400">WARNING:</strong> This will only work on RTX
          40-series, RX 7000-series, or Intel Arc GPU (and above).
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

  <div class="pt-6 border-t border-border mt-6">
    <div class="flex items-start justify-between">
      <div class="flex flex-col max-w-[80%]">
        <span class="text-sm font-bold text-main flex items-center gap-2">
          Enable Opus encoding
        </span>
        <p class="text-xs text-muted mt-1 leading-relaxed">
          Uses the Opus codec for slightly better audio quality at lower
          bitrates instead of standard AAC.<br />
          <strong class="text-red-400">WARNING:</strong> Do not enable this on macOS.
          Apple's video engine does not support Opus via HLS.
        </p>
      </div>

      <ToggleSwitch bind:checked={enableOpus} />
    </div>
  </div>
</div>
