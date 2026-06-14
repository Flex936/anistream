<script lang="ts">
    import CalendarCard from "$lib/components/calendar/CalendarCard.svelte";
    import { anilist } from "$wails/go/models";

    let {
        seasonalAnime,
        onSelectAnime,
    }: {
        seasonalAnime: anilist.Anime[];
        onSelectAnime?: (anime: anilist.Anime) => void;
    } = $props();

    const DAYS_OF_WEEK = [
        "Monday",
        "Tuesday",
        "Wednesday",
        "Thursday",
        "Friday",
        "Saturday",
        "Sunday",
    ];

    let now = $state(new Date());

    $effect(() => {
        const interval = setInterval(() => {
            now = new Date();
        }, 60000);

        return () => clearInterval(interval);
    });

    const calendar = $derived.by(() => {
        const grid = DAYS_OF_WEEK.reduce<Record<string, anilist.Anime[]>>(
            (acc, day) => {
                acc[day] = [];
                return acc;
            },
            {},
        );

        const activeAnime = seasonalAnime
            .filter((item) => item.nextAiringEpisode)
            .sort(
                (a, b) =>
                    a.nextAiringEpisode!.airingAt -
                    b.nextAiringEpisode!.airingAt,
            );

        activeAnime.forEach((item) => {
            const airDate = new Date(item.nextAiringEpisode!.airingAt * 1000);
            const localDay = DAYS_OF_WEEK[(airDate.getDay() + 6) % 7];
            grid[localDay].push(item);
        });

        return grid;
    });

    function formatLocalTime(timestamp: number) {
        return new Date(timestamp * 1000).toLocaleTimeString([], {
            hour: "2-digit",
            minute: "2-digit",
        });
    }

    function getTimeRemaining(timestamp: number) {
        const target = timestamp * 1000;
        const diff = target - now.getTime();

        if (diff <= 0) return "Airing now / Aired";

        const days = Math.floor(diff / (1000 * 60 * 60 * 24));
        const hours = Math.floor(
            (diff % (1000 * 60 * 60 * 24)) / (1000 * 60 * 60),
        );
        const minutes = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));

        if (days > 0) return `${days}d ${hours}h left`;
        if (hours > 0) return `${hours}h ${minutes}m left`;
        return `${minutes}m left`;
    }
</script>

<div class="w-full max-w-[1800px] mx-auto p-8 animate-in fade-in duration-300">
    <div class="flex items-center justify-between mb-8">
        <div>
            <h1 class="text-3xl font-bold text-main">Weekly Anime Schedule</h1>
            <p class="text-sm text-muted mt-1">
                Times are automatically adjusted to your local timezone.
            </p>
        </div>
    </div>

    <div class="grid grid-cols-7 gap-4 overflow-x-auto min-w-[1200px]">
        {#each DAYS_OF_WEEK as day}
            <div
                class="flex flex-col bg-surface rounded-xl border border-border p-3 min-h-48"
            >
                <h2
                    class="text-sm font-semibold text-main border-b border-border pb-2 mb-3 flex items-center justify-between"
                >
                    <span>{day}</span>
                    <span
                        class="text-[10px] font-normal bg-overlay text-muted px-1.5 py-0.5 rounded-full"
                    >
                        {calendar[day].length}
                    </span>
                </h2>

                <div
                    class="flex-1 overflow-y-auto space-y-4 custom-scrollbar pr-1"
                >
                    {#if calendar[day].length === 0}
                        <div class="text-xs text-muted text-center py-8 italic">
                            No releases
                        </div>
                    {:else}
                        {#each calendar[day] as anime (anime.id)}
                            <button
                                class="group w-full text-left focus:outline-none"
                                onclick={() => onSelectAnime?.(anime)}
                            >
                                <CalendarCard
                                    {anime}
                                    {formatLocalTime}
                                    {getTimeRemaining}
                                />
                            </button>
                        {/each}
                    {/if}
                </div>
            </div>
        {/each}
    </div>
</div>
