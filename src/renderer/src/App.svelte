<script lang="ts">
  import '../public/asset/reset.css';
  import './main.scss';
  import { settingUI } from './store';
  import Menu from './Menu.svelte';
  import Effect from './Effect.svelte';

  let cursor: boolean;
  let timer: boolean;
  let timerEvent: number;

  const setTimer = () => {
    cursor = false;
    if (timerEvent) clearTimeout(timerEvent);
    timerEvent = window.setTimeout(() => {
      cursor = true;
    }, 3000);
  };

  document.addEventListener('mousemove', setTimer);
  document.addEventListener('mousedown', setTimer);

  let video: HTMLVideoElement;
  let videoDeviceId: string | undefined;
  let audioDeviceId: string | undefined;
  let isChange = false;

  $: if (isChange === true) {
    isChange = false;
    navigator.mediaDevices
      .getUserMedia({
        audio: {
          deviceId: audioDeviceId ? { exact: audioDeviceId } : undefined,
          noiseSuppression: false,
          echoCancellation: false
        },
        video: {
          deviceId: videoDeviceId ? { exact: videoDeviceId } : undefined,
          width: 1920,
          height: 1080
        }
      })
      .then(function (stream) {
        video.srcObject = stream;
        video.play();
      })
      .catch(function (e) {
        console.log(e);
      });
  }
</script>

<main class:hidden={cursor === true}>
  <!-- svelte-ignore a11y-media-has-caption -->
  <video bind:this={video} id="videoElement" />
  <Effect bind:effect={$settingUI.effect} bind:veffect={$settingUI.veffect} bind:timer />
  <Menu
    bind:effect={$settingUI.effect}
    bind:veffect={$settingUI.veffect}
    bind:timer
    bind:videoDeviceId
    bind:audioDeviceId
    bind:isChange
  />
</main>
