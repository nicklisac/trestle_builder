<script>
  // Register platform view factory for the viewer iframe
  if (window._flutterWebViewRegistered) return;
  window._flutterWebViewRegistered = true;

  window.addEventListener('load', async () => {
    let io = null;
    let library = null;

    // Wait for Flutter to be ready
    const checkFlutter = setInterval(() => {
      if (window._flutter && window._flutter.bin) {
        clearInterval(checkFlutter);
        io = window._flutter.bin;
        library = io.loadLibrary('ui_web__web__platform_view__');
        if (library) {
          library.registerPlatformViewType(
            'viewer-html',
            (id, viewHeight, viewWidth) => {
              const iframe = document.createElement('iframe');
              iframe.id = 'viewer-iframe-' + id;
              iframe.width = '100%';
              iframe.height = '100%';
              iframe.style.border = 'none';
              iframe.style.position = 'absolute';
              iframe.style.top = '0';
              iframe.style.left = '0';
              iframe.src = 'assets/viewer.html';
              iframe.allow = 'fullscreen';

              const div = document.createElement('div');
              div.appendChild(iframe);
              div.style.width = '100%';
              div.style.height = '100%';
              div.style.position = 'relative';

              return div;
            }
          );
        }
      }
    }, 100);
  });
</script>
