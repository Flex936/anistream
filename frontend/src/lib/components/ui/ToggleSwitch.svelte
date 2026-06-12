<script lang="ts">
  let {
    checked = $bindable(),
    disabled = false,
    theme = "primary",
  }: {
    checked: boolean;
    disabled?: boolean;
    theme?: "primary" | "amber";
  } = $props();
</script>

<button
  type="button"
  aria-label="Toggle setting"
  {disabled}
  class="relative mt-2 inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors
         focus:outline-none focus:ring-2 focus:ring-primary
         disabled:opacity-30 disabled:cursor-not-allowed
         {checked
    ? theme === 'amber'
      ? 'bg-amber-500'
      : 'bg-primary'
    : 'bg-gray-600'}"
  onclick={() => (checked = !checked)}
>
  <span
    class="inline-block h-4 w-4 transform rounded-full bg-white transition-transform
           {checked ? 'translate-x-6' : 'translate-x-1'}"
  ></span>
</button>
