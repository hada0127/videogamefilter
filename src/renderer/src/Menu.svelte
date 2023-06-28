<script lang="ts">
  import './Menu.scss';
  export let effect: string;
  export let veffect: string;
  export let timer: boolean;
</script>

<div class="menu" class:hidden={timer === true}>
  <label>
    <p>Horizontal Effect</p>
    <select bind:value={effect}>
      <option value="">None</option>
      <option value="scanline10">Scanline 10%</option>
      <option value="scanline20">Scanline 20%</option>
      <option value="scanline30">Scanline 30%</option>
      <option value="scanline40">Scanline 40%</option>
      <option value="scanline50">Scanline 50%</option>
    </select>
  </label>
  <label>
    <p>Vertical Effect</p>
    <select bind:value={veffect}>
      <option value="">None</option>
      <option value="scanline10">Scanline 10%</option>
      <option value="scanline20">Scanline 20%</option>
      <option value="scanline30">Scanline 30%</option>
      <option value="scanline40">Scanline 40%</option>
      <option value="scanline50">Scanline 50%</option>
    </select>
  </label>
</div>
