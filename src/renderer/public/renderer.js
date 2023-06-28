/* eslint-disable @typescript-eslint/no-unused-vars */
/* eslint-disable @typescript-eslint/no-var-requires */
const { ipcRenderer } = require('electron');

const remote = require('@electron/remote');

//포트 목록
// async function serialportList() {
//   try{
//     await SerialPort.list().then((ports, err) => {
//       if(err) {
//         return err;
//       } else {
//         console.log(ports);
//         return ports;
//       }
//     });
//   } catch(err) {
//     return err;
//   }
// }

//최상단 고정
function setAlwaysOnTop(flag) {
  const win = remote.getCurrentWindow();
  if(flag === true) {
    win.setAlwaysOnTop(true, 'normal');
    win.setMinimizable(false);
    win.moveTop();
  } else {
    win.setAlwaysOnTop(false);
    win.setMinimizable(true);
  }
  console.log('setAlwaysOnTop',flag);
}

function sendTop(){
  const win = remote.getCurrentWindow();
  win.moveTop();
}


//창 크기 변경
function setWindowSize(x, y, width, target='main'){
  const win = remote.getCurrentWindow();
  const screenWidth = screen.width;
  const screenHeight = screen.availHeight;

  const mainBaseWidth = 1200;
  const mainBaseHeight = 800;
  const smallBaseWidth = 200;
  const smallBaseHeight = 50;
  let useWidth = parseInt(width);
  let useHeight;
  let useZoom = 0;
  let useX, useY;

  if(target == 'small'){
    useWidth =
      parseInt(useWidth) > smallBaseWidth/2
        ? parseInt(useWidth)
        : smallBaseWidth/2;
    useZoom = parseInt(useWidth) / smallBaseWidth;
    useHeight = parseInt(useZoom * smallBaseHeight);
  } else {
    useWidth =
      parseInt(useWidth) > mainBaseWidth/2
        ? parseInt(useWidth)
        : mainBaseWidth/2;
    useZoom = parseInt(useWidth) / mainBaseWidth;
    useHeight = parseInt(useZoom * mainBaseHeight);  
  }

  switch(x) {
    case 'left' : 
      useX = 0;
      break;
    case 'right' :
      useX = screenWidth - useWidth;
      break;
    case 'center' :
      useX = (screenWidth - useWidth)/2;
      break;
    default :
      useX = parseInt(x) < 0 ? 0:parseInt(x) < screenWidth - useWidth ? parseInt(x) : screenWidth - useWidth;
      break;
  }
  switch(y) {
    case 'top' : 
      useY = 0;
      break;
    case 'bottom' :
      useY = screenHeight - useHeight;
      break;
    case 'center' :
      useY = (screenHeight - useHeight)/2;
      break;
    default :
    useY = parseInt(y) < 0 ? 0:parseInt(y) < screenHeight - useHeight ? parseInt(y) : screenHeight - useHeight;
      break;
  }
  useX = parseInt(useX);
  useY = parseInt(useY);
  //console.log(useX, useY, useWidth, useHeight,useZoom);
  win.setBounds({
    x: useX,
    y: useY,
    width: useWidth,
    height: useHeight
  }); 
  if (useZoom > 0) {
    document.querySelector("body").style.zoom = useZoom < 0.5 ? 0.5 : useZoom;
  }
}