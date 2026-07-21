import { apiInitializer } from "discourse/lib/api";
import { ajax } from "discourse/lib/ajax";
import { getCurrentPushSubscription } from "discourse/lib/push-notifications";

let syncInFlight = null;

async function syncSubscription() {
  if (syncInFlight) {
    return syncInFlight;
  }

  syncInFlight = (async () => {
    const subscription = await getCurrentPushSubscription();
    await ajax("/reliable-push/subscriptions/sync", {
      type: "POST",
      data: { subscription },
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

export default apiInitializer((api) => {
  const currentUser = api.getCurrentUser();
  const siteSettings = api.container.lookup("service:site-settings");

  if (!currentUser || !siteSettings.reliable_push_enabled) {
    return;
  }

  syncSubscription();

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.addEventListener("controllerchange", syncSubscription);
  }

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      syncSubscription();
    }
  });
});
