/* eslint-disable @typescript-eslint/no-var-requires */
// This file is the entry point for the Electron application.

const { app, BrowserWindow } = require('electron')

process.env['ELECTRON_DISABLE_SECURITY_WARNINGS'] = 'true';

// single instance lock 요청
const gotTheLock = app.requestSingleInstanceLock();

if (!gotTheLock) {
  app.quit();
}

function createWindow() {
  const win = new BrowserWindow({
    width: 1200,
    height: 800,
    frame: true,
    center: true,
    resizable: true,
    fullscreen: false,
    fullscreenable: true,
    webPreferences: {
        nodeIntegration: true,
        contextIsolation: false, 
        enableRemoteModule: true
    }
  })

  
  if (process.env.NODE_ENV !== 'development') {
    // Load production build
    win.loadFile(`${__dirname}/renderer/dist/index.html`)
  } else {
    // Load vite dev server page 
    console.log('Development mode')
    win.loadURL('http://localhost:3000/')
  }

  require('@electron/remote/main').initialize();
  require("@electron/remote/main").enable(win.webContents);  
}

app.whenReady()
  .then(() => {
    createWindow()

    app.on('activate', function () {
      if (BrowserWindow.getAllWindows().length === 0) createWindow()
    })
  })

app.on('window-all-closed', function () {
  if (process.platform !== 'darwin') app.quit()
})