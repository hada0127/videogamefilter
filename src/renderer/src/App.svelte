<script lang="ts">
  import '../public/asset/reset.css';
  import './main.scss';
  import { settingUI } from './store';
  import Menu from './Menu.svelte';
  import Effect from './Effect.svelte';
  /**
   * https://stackoverflow.com/questions/75718090/getusermedia-issue-with-permissions-and-domexception-could-not-start-video-so
   */
  let timer: boolean;
  let timerEvent: number;

  const setTimer = () => {
    timer = false;
    if (timerEvent) clearTimeout(timerEvent);
    timerEvent = window.setTimeout(() => {
      timer = true;
    }, 5000);
  };

  document.addEventListener('mousemove', setTimer);
  document.addEventListener('mousedown', setTimer);
</script>

<main>
  <img src="asset/temp.png" alt="" />
  <Effect bind:effect={$settingUI.effect} bind:veffect={$settingUI.veffect} />
  <Menu bind:effect={$settingUI.effect} bind:veffect={$settingUI.veffect} bind:timer />
</main>
