import path from 'path'
import process from 'process'
import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import sveltePreprocess from 'svelte-preprocess'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [svelte({
		preprocess: sveltePreprocess(),
	})],
  resolve: {
    alias: {
      '@': path.resolve('src/renderer/src'),
    },
  },
  root: path.resolve(process.cwd(), 'src/renderer'),
  base: './',
})
