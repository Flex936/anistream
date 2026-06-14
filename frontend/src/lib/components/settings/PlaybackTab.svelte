<script lang="ts">
  import { Monitor, ExternalLink, TriangleAlert } from "@lucide/svelte";
  import ToggleSwitch from "$lib/components/ui/ToggleSwitch.svelte";

  let {
    internalPlayback = $bindable(),
  } = $props();
</script>

<div class="animate-in fade-in slide-in-from-right-4 duration-300 pb-4">
  <h3 class="text-2xl font-bold text-main mb-2">Playback Mode</h3>
  <p class="text-sm text-muted mb-6">
    Choose how MPV renders the video.
  </p>

  <div class="space-y-6">
    <!-- Internal playback toggle -->
    <div class="flex items-start justify-between p-4 rounded-xl border-2 transition-all duration-200
               {internalPlayback ? 'border-primary bg-primary/10' : 'border-border bg-base'}">
      <div class="flex items-start gap-4">
        <div class="p-2 rounded-lg mt-0.5 {internalPlayback ? 'bg-primary text-white' : 'bg-surface text-muted'}">
          {#if internalPlayback}
            <Monitor size={20} />
          {:else}
            <ExternalLink size={20} />
          {/if}
        </div>
        <div class="flex flex-col">
          <span class="font-bold text-main">Internal Playback</span>
          <p class="text-xs text-muted mt-1 leading-relaxed max-w-md">
            {#if internalPlayback}
              Video renders <strong class="text-primary">inside</strong> the application window. Controls overlay
              directly on top of the video.
            {:else}
              Video opens in a <strong class="text-main">separate MPV window</strong>. Controls remain in the app
              while the video plays externally.
            {/if}
          </p>
        </div>
      </div>
      <ToggleSwitch bind:checked={internalPlayback} />
    </div>

    <!-- Info / restart notice -->
    <div class="flex items-start gap-2 p-3 rounded-lg bg-amber-500/5 border border-amber-500/20">
      <TriangleAlert class="text-amber-400 shrink-0 mt-0.5" size={14} />
      <p class="text-xs text-amber-400/90 leading-relaxed">
        Changing this setting requires an <strong>app restart</strong> to take effect.
      </p>
    </div>
  </div>
</div>
