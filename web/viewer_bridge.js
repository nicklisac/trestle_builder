// JavaScript bridge for Flutter Web -> Viewer communication
window._sendToViewer = function(msg) {
  var iframe = document.getElementById('viewer-iframe');
  if (iframe && iframe.contentWindow) {
    iframe.contentWindow.postMessage(msg, '*');
  }
};
