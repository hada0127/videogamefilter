<script lang="ts">
  import './Menu.scss';
  export let effect: string;
  export let veffect: string;
  export let timer: boolean;

  export let deviceId: string | undefined;

  type MediaDevice = {
    deviceId: string;
    kind: string;
    label: string;
  };
  let devices: {
    deviceId: string;
    label: string;
  }[] = [];

  function gotDevices(mediaDevices: MediaDevice[]) {
    let i = 0;
    mediaDevices.forEach((mediaDevice: MediaDevice) => {
      if (mediaDevice.kind === 'videoinput') {
        let tmp = {
          deviceId: mediaDevice.deviceId,
          label: mediaDevice.label
        };
        if (i === 0) {
          deviceId = mediaDevice.deviceId;
          i++;
        }
        devices.push(tmp);
      }
    });
    devices = devices;
    console.log(devices);
  }
  navigator.mediaDevices.enumerateDevices().then(gotDevices);
</script>

<div class="menu" class:hidden={timer === true}>
  <label>
    <p>Device</p>
    {#key devices}
      <select bind:value={deviceId}>
        {#each devices as device}
          <option value={device.deviceId}>{device.label}</option>
        {/each}
      </select>
    {/key}
  </label>
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
