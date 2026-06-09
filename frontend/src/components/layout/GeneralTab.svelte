<script lang="ts">
  import ToggleSwitch from "./ToggleSwitch.svelte";

  let {
    selectedRes = $bindable(),
    resolutions,
    filterEcchi = $bindable(),
  } = $props();
</script>

<div class="animate-in fade-in slide-in-from-right-4 duration-300 pb-4">
  <h3 class="text-2xl font-bold text-main mb-6">General Settings</h3>

  <div class="space-y-6">
    <div class="space-y-3">
      <span class="text-xs font-semibold text-muted uppercase tracking-wider">
        Startup Resolution
      </span>
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
              class="font-bold text-sm {selectedRes.label === res.label
                ? 'text-primary'
                : 'text-gray-200'}"
            >
              {res.label.split("(")[0]}
            </span>
            <span
              class="text-[10px] {selectedRes.label === res.label
                ? 'text-primary/80'
                : 'text-gray-500'}"
            >
              {res.w} x {res.h}
            </span>
          </button>
        {/each}
      </div>
    </div>

    <div class="pt-6 border-t border-border flex items-center justify-between">
      <div>
        <span
          class="text-sm font-semibold text-main uppercase tracking-wider block"
          >Filter Ecchi Content</span
        >
        <span class="text-xs text-muted">Hide borderline NSFW shows.</span>
      </div>
      <ToggleSwitch bind:checked={filterEcchi} />
    </div>
  </div>
</div>
