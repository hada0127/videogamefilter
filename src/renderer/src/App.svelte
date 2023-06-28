<script lang="ts">
  import '../public/asset/reset.css';
  import './main.scss';
  import { settingUI } from './store';
  import Menu from './Menu.svelte';
  import Effect from './Effect.svelte';
  /**
   * https://stackoverflow.com/questions/75718090/getusermedia-issue-with-permissions-and-domexception-could-not-start-video-so
   */
  let cursor: boolean;
  let timer: boolean;
  let timerEvent: number;

  const setTimer = () => {
    cursor = false;
    if (timerEvent) clearTimeout(timerEvent);
    timerEvent = window.setTimeout(() => {
      // timer = true;
      cursor = true;
    }, 3000);
  };

  document.addEventListener('mousemove', setTimer);
  document.addEventListener('mousedown', setTimer);

  let video: HTMLVideoElement;
  let deviceId: string | undefined;

  $: if (deviceId) {
    console.log(deviceId);
    navigator.mediaDevices
      .getUserMedia({
        video: {
          deviceId: {
            exact: deviceId
          }
        },
        audio: false
      })
      .then(function (stream) {
        video.srcObject = stream;
      })
      .catch(function () {
        console.log('Something went wrong!');
      });
  }
</script>

<main class:hidden={cursor === true}>
  <!-- svelte-ignore a11y-media-has-caption -->
  <video bind:this={video} autoplay muted id="videoElement" />
  <Effect bind:effect={$settingUI.effect} bind:veffect={$settingUI.veffect} bind:timer />
  <Menu
    bind:effect={$settingUI.effect}
    bind:veffect={$settingUI.veffect}
    bind:timer
    bind:deviceId
  />
</main>
