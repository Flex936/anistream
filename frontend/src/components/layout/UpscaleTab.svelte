<script lang="ts">
    import {
        MoveHorizontal,
        MoveVertical,
        TriangleAlert,
        X,
    } from "@lucide/svelte";

    let {
        upscalingMethod = $bindable(),
        upscalingResolution = $bindable(),
        upscalers,
        targetResolutions,
    } = $props();
</script>

<div class="animate-in fade-in slide-in-from-right-4 duration-300 pb-4">
    <h3 class="text-2xl font-bold text-main mb-2">Upscaling settings</h3>
    <p class="text-sm text-muted mb-6">
        Upscale the output for higher fidelity.
    </p>

    <div class="space-y-6">
        <div class="space-y-3">
            <span
                class="text-xs font-semibold text-muted uppercase tracking-wider"
            >
                Upscaling Method
            </span>
        </div>

        <div class="grid grid-cols-2 gap-3">
            {#each upscalers as method}
                <button
                    class="flex flex-col items-start p-3 rounded-xl border-2 transition-all duration-200 {method.id ===
                    upscalingMethod
                        ? 'border-primary bg-primary/10'
                        : 'border-border bg-base hover:border-gray-500'}"
                    onclick={() => (upscalingMethod = method.id)}
                >
                    <span
                        class="font-bold text-sm {method.id === upscalingMethod
                            ? 'text-primary'
                            : 'text-gray-200'}"
                    >
                        {method.name}
                    </span>
                    <span
                        class="text-xs text-muted {method.id === upscalingMethod
                            ? 'text-primary/80'
                            : 'text-gray-500'}"
                    >
                        {method.desc}
                    </span>
                </button>
            {/each}
        </div>

        <div class="space-y-3">
            <span
                class="text-xs font-semibold text-muted uppercase tracking-wider"
            >
                Target Resolution
            </span>
        </div>

        <div class="space-y-3">
            {#each targetResolutions as resolution}
                <button
                    class="w-full flex items-center p-4 rounded-xl border-2 transition-all duration-200 {upscalingResolution.id ===
                    resolution.id
                        ? 'border-primary bg-primary/10'
                        : 'border-border bg-base hover:border-gray-500 text-left'} {upscalingMethod ===
                    ''
                        ? 'opacity-40 cursor-not-allowed select-none'
                        : ''}"
                    onclick={() => (upscalingResolution = { ...resolution })}
                    disabled={upscalingMethod === ""}
                >
                    <div class="flex flex-col text-left">
                        <span
                            class="font-bold {upscalingResolution.id ===
                            resolution.id
                                ? 'text-primary'
                                : 'text-main'}"
                        >
                            {resolution.label}
                        </span>
                    </div>
                </button>
            {/each}

            <button
                class="w-full flex items-center p-4 rounded-xl border-2 transition-all duration-200 {upscalingResolution.id ===
                '4'
                    ? 'border-primary bg-primary/10'
                    : 'border-border bg-base hover:border-gray-500 text-left'} {upscalingMethod ===
                ''
                    ? 'opacity-40 cursor-not-allowed select-none'
                    : ''}"
                disabled={upscalingMethod === ""}
                onclick={() =>
                    (upscalingResolution = { ...upscalingResolution, id: "4" })}
            >
                <div class="flex flex-col text-left">
                    <span
                        class="font-bold {upscalingResolution.id === '4'
                            ? 'text-primary'
                            : 'text-main'}"
                    >
                        Custom Resolution
                    </span>
                </div>
            </button>
        </div>

        <div class="space-y-3">
            <span
                class="text-xs font-semibold text-muted uppercase tracking-wider"
            >
                Custom Resolution Config
            </span>
        </div>

        <div
            class="flex items-center gap-3 font-medium transition-all duration-200
    {upscalingResolution.id !== '4' || upscalingMethod === ''
                ? 'opacity-40 cursor-not-allowed select-none'
                : ''}"
        >
            <div class="relative flex items-center">
                <MoveHorizontal
                    class="pointer-events-none absolute left-3 h-4 w-4 text-muted/70"
                />
                <input
                    type="number"
                    disabled={upscalingResolution.id != "4" ||
                        upscalingMethod === ""}
                    bind:value={upscalingResolution.w}
                    min="1"
                    placeholder="Width"
                    class="w-32 rounded-xl border-2 border-border bg-base py-2 pl-9 pr-8 text-center text-sm text-main shadow-sm transition-all placeholder:text-muted/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 disabled:cursor-not-allowed [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none invalid:focus:border-red-500 invalid:focus:ring-red-500/70 invalid:border-red-500"
                />
                <span
                    class="pointer-events-none absolute right-3 text-xs text-muted/70"
                    >px</span
                >
            </div>

            <X class="h-4 w-4 shrink-0 text-muted" />

            <div class="relative flex items-center">
                <MoveVertical
                    class="pointer-events-none absolute left-3 h-4 w-4 text-muted/70"
                />
                <input
                    type="number"
                    disabled={upscalingResolution.id != "4" ||
                        upscalingMethod === ""}
                    bind:value={upscalingResolution.h}
                    min="1"
                    placeholder="Height"
                    class="w-32 rounded-xl border-2 border-border bg-base py-2 pl-9 pr-8 text-center text-sm text-main shadow-sm transition-all placeholder:text-muted/50 focus:border-primary focus:outline-none focus:ring-2 focus:ring-primary/20 disabled:cursor-not-allowed [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none invalid:focus:border-red-500 invalid:focus:ring-red-500/70 invalid:border-red-500"
                />
                <span
                    class="pointer-events-none absolute right-3 text-xs text-muted/70"
                    >px</span
                >
            </div>
        </div>
        <div>
            <span class="text-xs text-muted mb-2 flex row">
                Adjust these to your own resolution.
            </span>
            <div class="relative flex items-center">
                <TriangleAlert
                    class="text-amber-400 pointer-events-none mr-2"
                    size={16}
                />
                <span class="text-xs text-amber-400">
                    Be advised there is no upper limit.
                </span>
            </div>
        </div>
    </div>
</div>
