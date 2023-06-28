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
    frame: false,
    //    alwaysOnTop: true,
    center: true,
    resizable: false,
    fullscreen: false,        
    webPreferences: {
        nodeIntegration: true, // to allow require
        contextIsolation: false, // allow use with Electron 12+
        // preload: path.join(__dirname, 'preload.js'),
        enableRemoteModule: true
    }
  })

  
  win.loadFile(`../renderer/dist/index.html`)

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