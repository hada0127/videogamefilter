<script lang="ts">
  import './Effect.scss';
  export let effect = '0';
  export let veffect = '0';
  export let timer: boolean;
</script>

<div class="veffect" style="opacity: {veffect}" />
<!-- svelte-ignore a11y-click-events-have-key-events -->
<div
  class="effect"
  style="opacity: {effect}"
  on:click={() => {
    timer = !timer;
  }}
/>
