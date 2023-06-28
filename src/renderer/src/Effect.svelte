<script lang="ts">
  import './Effect.scss';
  export let effect: string;
  export let veffect: string;
  export let timer: boolean;
</script>

<div
  class="veffect"
  class:scanline10={veffect === 'scanline10'}
  class:scanline20={veffect === 'scanline20'}
  class:scanline30={veffect === 'scanline30'}
  class:scanline40={veffect === 'scanline40'}
  class:scanline50={veffect === 'scanline50'}
/>
<!-- svelte-ignore a11y-click-events-have-key-events -->
<div
  class="effect"
  class:scanline10={effect === 'scanline10'}
  class:scanline20={effect === 'scanline20'}
  class:scanline30={effect === 'scanline30'}
  class:scanline40={effect === 'scanline40'}
  class:scanline50={effect === 'scanline50'}
  on:click={() => {
    timer = !timer;
  }}
/>
