import { writable } from 'svelte/store'

/*
UI 설정
*/
const storedSettingUI = localStorage.settingUI && JSON.parse(localStorage.settingUI);
export const settingUI = writable(storedSettingUI || {
	effect: '',
	veffect: ''
});
settingUI.subscribe((value) => localStorage.settingUI = JSON.stringify(value));