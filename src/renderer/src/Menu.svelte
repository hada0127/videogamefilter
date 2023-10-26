<script lang="ts">
  import './Menu.scss';
  export let effect: string;
  export let veffect: string;
  export let timer: boolean;
  export let isChange: boolean;
  export let videoDeviceId: string | undefined;
  export let audioDeviceId: string | undefined;

  type MediaDevice = {
    deviceId: string;
    kind: string;
    label: string;
  };
  let devices: {
    deviceId: string;
    label: string;
  }[] = [];
  let videoDevices: {
    deviceId: string;
    label: string;
  }[] = [];
  let audioDevices: {
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
          videoDeviceId = mediaDevice.deviceId;
          i++;
        }
        videoDevices.push(tmp);
        devices.push(tmp);
      }
      if (mediaDevice.kind === 'audioinput') {
        let tmp = {
          deviceId: mediaDevice.deviceId,
          label: mediaDevice.label
        };
        if (i === 0) {
          audioDeviceId = mediaDevice.deviceId;
          i++;
        }
        audioDevices.push(tmp);
        devices.push(tmp);
      }
    });
    videoDevices = videoDevices;
    audioDevices = audioDevices;
    isChange = true;
  }

  navigator.mediaDevices.enumerateDevices().then(gotDevices);
  const videoHandleSelect = (event: Event) => {
    const inputElement = event.target as HTMLSelectElement;
    videoDeviceId = inputElement.value === null ? undefined : inputElement.value;
    isChange = true;
  };
  const audioHandleSelect = (event: Event) => {
    const inputElement = event.target as HTMLSelectElement;
    audioDeviceId = inputElement.value === null ? undefined : inputElement.value;
    isChange = true;
  };
  // scanlineList 는 key value 형태의 값을 갖는다.
  const scanlineList = {
    '0': 'None',
    '0.05': 'Scanline 5%',
    '0.1': 'Scanline 10%',
    '0.15': 'Scanline 15%',
    '0.2': 'Scanline 20%',
    '0.25': 'Scanline 25%',
    '0.3': 'Scanline 30%',
    '0.35': 'Scanline 35%',
    '0.4': 'Scanline 40%',
    '0.45': 'Scanline 45%',
    '0.5': 'Scanline 50%'
  };
</script>

<div class="menu" class:hidden={timer === true}>
  <label>
    <p>Video</p>
    {#key videoDevices}
      <select on:change={videoHandleSelect}>
        {#each videoDevices as device}
          <option value={device.deviceId}>{device.label}</option>
        {/each}
      </select>
    {/key}
  </label>
  <label>
    <p>Audio</p>
    {#key audioDevices}
      <select on:change={audioHandleSelect}>
        {#each audioDevices as device}
          <option value={device.deviceId}>{device.label}</option>
        {/each}
      </select>
    {/key}
  </label>
  <label>
    <p>Horizontal Effect</p>
    <select bind:value={effect}>
      {#each Object.entries(scanlineList) as [k, v]}
        <option value={k}>{v}</option>
      {/each}
    </select>
  </label>
  <label>
    <p>Vertical Effect</p>
    <select bind:value={veffect}>
      {#each Object.entries(scanlineList) as [k, v]}
        <option value={k}>{v}</option>
      {/each}
    </select>
  </label>
</div>
