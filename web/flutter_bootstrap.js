{{flutter_js}}
{{flutter_build_config}}

const loading = document.getElementById('jobmate-loading');
const message = document.getElementById('jobmate-startup-message');

function showStartupFailure() {
  if (message) message.textContent = 'Unable to start JobMate. Check your connection and reload.';
  const reload = document.getElementById('jobmate-reload');
  if (reload) reload.hidden = false;
}

// Keep the loading message until Flutter has actually drawn its first frame.
window.addEventListener('flutter-first-frame', () => {
  requestAnimationFrame(() => requestAnimationFrame(() => {
    if (loading) loading.style.display = 'none';
  }));
}, { once: true });

try {
  Promise.resolve(_flutter.loader.load({
    onEntrypointLoaded: async function(engineInitializer) {
      try {
        if (message) message.textContent = 'Starting JobMate…';
        const appRunner = await engineInitializer.initializeEngine();
        await appRunner.runApp();
      } catch (_) {
        showStartupFailure();
      }
    }
  })).catch(showStartupFailure);
} catch (_) {
  showStartupFailure();
}
