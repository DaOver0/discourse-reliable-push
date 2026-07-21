import { ajax } from "discourse/lib/ajax";
import { apiInitializer } from "discourse/lib/api";

let syncInFlight = null;
let audioContext = null;
let baseTitle = null;
let blinkTimer = null;
let blinkCount = 0;

async function getCurrentPushSubscription() {
  if (!("serviceWorker" in navigator) || !("PushManager" in window)) {
    return null;
  }

  const registration = await navigator.serviceWorker.ready;
  return registration.pushManager.getSubscription();
}

function serializableSubscription(subscription) {
  if (!subscription) {
    return null;
  }

  return typeof subscription.toJSON === "function"
    ? subscription.toJSON()
    : subscription;
}

async function syncSubscription() {
  if (syncInFlight) {
    return syncInFlight;
  }

  syncInFlight = (async () => {
    const subscription = await getCurrentPushSubscription();
    await ajax("/reliable-push/subscriptions/sync", {
      type: "POST",
      contentType: "application/json",
      data: JSON.stringify({
        subscription: serializableSubscription(subscription),
      }),
    });
  })()
    .catch((error) => {
      // eslint-disable-next-line no-console
      console.error("Reliable Push subscription sync failed", error);
    })
    .finally(() => {
      syncInFlight = null;
    });

  return syncInFlight;
}

function unlockAudio() {
  if (audioContext) {
    return;
  }

  const AudioContext = window.AudioContext || window.webkitAudioContext;
  if (!AudioContext) {
    return;
  }

  try {
    audioContext = new AudioContext();
    if (audioContext.state === "suspended") {
      audioContext.resume();
    }
  } catch (_error) {
    audioContext = null;
  }
}

function playAttentionSound() {
  if (!audioContext) {
    return;
  }

  if (audioContext.state === "suspended") {
    audioContext.resume().catch(() => {});
  }

  if (audioContext.state !== "running") {
    return;
  }

  try {
    const oscillator = audioContext.createOscillator();
    const gain = audioContext.createGain();
    const now = audioContext.currentTime;

    oscillator.type = "sine";
    oscillator.frequency.setValueAtTime(880, now);
    oscillator.frequency.setValueAtTime(660, now + 0.12);
    gain.gain.setValueAtTime(0.0001, now);
    gain.gain.exponentialRampToValueAtTime(0.08, now + 0.02);
    gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.28);

    oscillator.connect(gain);
    gain.connect(audioContext.destination);
    oscillator.start(now);
    oscillator.stop(now + 0.3);
  } catch (_error) {
    // Browser audio policies may still reject playback. Web Push remains active.
  }
}

function stopTitleBlink() {
  if (blinkTimer) {
    window.clearInterval(blinkTimer);
    blinkTimer = null;
  }

  blinkCount = 0;
  if (baseTitle) {
    document.title = baseTitle;
  }
}

function startTitleBlink() {
  if (document.visibilityState === "visible") {
    return;
  }

  if (!blinkTimer) {
    baseTitle = document.title;
  }
  blinkCount += 1;

  if (blinkTimer) {
    return;
  }

  let highlighted = false;
  blinkTimer = window.setInterval(() => {
    highlighted = !highlighted;
    document.title = highlighted
      ? `🔔 (${blinkCount}) ${baseTitle}`
      : baseTitle;
  }, 900);
}

function installPreferenceApi(currentUser) {
  window.ReliablePushPreferences = {
    async load() {
      return ajax("/reliable-push/preferences");
    },

    async save(preferences) {
      const response = await ajax("/reliable-push/preferences", {
        type: "PUT",
        contentType: "application/json",
        data: JSON.stringify({ preferences }),
      });

      currentUser.reliable_push_preferences = response.preferences;
      return response.preferences;
    },
  };
}

export default apiInitializer((api) => {
  const currentUser = api.getCurrentUser();
  const siteSettings = api.container.lookup("service:site-settings");

  if (!currentUser || !siteSettings.reliable_push_enabled) {
    return;
  }

  baseTitle = document.title;
  installPreferenceApi(currentUser);
  syncSubscription();

  document.addEventListener("pointerdown", unlockAudio, {
    capture: true,
    once: true,
  });
  document.addEventListener("keydown", unlockAudio, {
    capture: true,
    once: true,
  });

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.addEventListener("controllerchange", syncSubscription);
  }

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      stopTitleBlink();
      syncSubscription();
    }
  });
  window.addEventListener("focus", stopTitleBlink);

  const messageBus = api.container.lookup("service:message-bus");
  messageBus.subscribe(`/reliable-push/${currentUser.id}`, (message) => {
    if (message?.sound) {
      playAttentionSound();
    }
    if (message?.tab_blink) {
      startTitleBlink();
    }
  });
});
