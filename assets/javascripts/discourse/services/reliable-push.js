import { tracked } from "@glimmer/tracking";
import { action } from "@ember/object";
import Service, { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import {
  keyValueStore,
  userSubscriptionKey,
} from "discourse/lib/push-notifications";

// This service never registers its own worker or installs a second push handler.
// Core Discourse (including Chat) remains the sole source of notifications.
const RECHECK_MS = 60 * 1000;
const WORKER_TIMEOUT_MS = 8000;

export default class ReliablePushService extends Service {
  @service currentUser;
  @service siteSettings;
  @service capabilities;
  @service desktopNotifications;

  @tracked status = "checking";
  @tracked busy = false;
  @tracked testResult = null;

  _started = false;
  _lastCheck = 0;
  _inFlight = null;
  _workerChange = null;
  _visibilityChange = null;
  _focus = null;
  _online = null;

  get statusKey() {
    return `discourse_reliable_push.${this.status}`;
  }

  get canEnable() {
    return (
      !this.busy &&
      this.status !== "ready" &&
      this.status !== "unsupported" &&
      this.status !== "denied" &&
      this.status !== "unavailable_key"
    );
  }

  get canTest() {
    return (
      !this.busy &&
      this.status === "ready" &&
      this.siteSettings.reliable_push_test_notifications
    );
  }

  get supported() {
    return (
      typeof navigator !== "undefined" &&
      typeof Notification !== "undefined" &&
      "serviceWorker" in navigator &&
      "PushManager" in window &&
      typeof ServiceWorkerRegistration !== "undefined" &&
      !this.capabilities.isAppWebview &&
      "showNotification" in ServiceWorkerRegistration.prototype
    );
  }

  start() {
    if (this._started || !this.currentUser || !this.siteSettings.reliable_push_enabled) {
      return;
    }
    this._started = true;
    this._workerChange = () => this.check();
    this._visibilityChange = () => {
      if (document.visibilityState === "visible") {
        this.check();
      }
    };
    this._focus = () => this.check();
    this._online = () => this.check({ force: true });
    if (this.supported) {
      navigator.serviceWorker.addEventListener("controllerchange", this._workerChange);
      document.addEventListener("visibilitychange", this._visibilityChange);
      window.addEventListener("focus", this._focus);
      window.addEventListener("online", this._online);
    }
    this.check({ force: true });
  }

  willDestroy() {
    if (this._started && this.supported) {
      navigator.serviceWorker.removeEventListener("controllerchange", this._workerChange);
      document.removeEventListener("visibilitychange", this._visibilityChange);
      window.removeEventListener("focus", this._focus);
      window.removeEventListener("online", this._online);
    }
    super.willDestroy(...arguments);
  }

  async _registration() {
    // Unlike core's initial-visit capability check, do not require a controller:
    // the first PWA page can have an active worker without being controlled yet.
    // Core can register its worker asynchronously on the first page load.
    // Briefly recheck before diagnosing it as missing.
    let existing = await navigator.serviceWorker.getRegistration();
    for (let attempt = 0; !existing && attempt < 4; attempt++) {
      await new Promise((resolve) => setTimeout(resolve, 250));
      existing = await navigator.serviceWorker.getRegistration();
    }
    if (!existing) {
      return null;
    }
    let timeout;
    try {
      return await Promise.race([
        navigator.serviceWorker.ready,
        new Promise((_, reject) => {
          timeout = setTimeout(() => reject(new Error("worker_timeout")), WORKER_TIMEOUT_MS);
        }),
      ]);
    } finally {
      clearTimeout(timeout);
    }
  }

  _vapidKey() {
    const value = this.siteSettings.vapid_public_key_bytes;
    if (typeof value !== "string") {
      return null;
    }
    const bytes = value.split("|").map(Number);
    if (bytes.length !== 65 || bytes.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) {
      return null;
    }
    return new Uint8Array(bytes);
  }

  async _syncToServer(subscription) {
    const response = await ajax("/reliable-push/sync", {
      type: "POST",
      data: { subscription: subscription.toJSON() },
    });
    return response.registered === true;
  }

  async _performCheck({ allowRepair = true } = {}) {
    if (!this.currentUser || !this.siteSettings.reliable_push_enabled || !this.supported) {
      this.status = "unsupported";
      return;
    }
    if (Notification.permission === "denied") {
      this.status = "denied";
      return;
    }
    if (Notification.permission !== "granted") {
      this.status = "not_enabled";
      return;
    }

    const registration = await this._registration();
    if (!registration || !registration.pushManager) {
      this.status = "no_worker";
      return;
    }

    const marker = keyValueStore.getItem(userSubscriptionKey(this.currentUser));
    // Core writes an empty string when a user switches off push. Respect it.
    if (marker === "") {
      this.status = "not_enabled";
      return;
    }

    let subscription = await registration.pushManager.getSubscription();
    if (!subscription) {
      if (marker !== "subscribed") {
        this.status = "not_enabled";
        return;
      }
      if (!allowRepair || !this.siteSettings.reliable_push_auto_repair) {
        this.status = "repair_needed";
        return;
      }
      const key = this._vapidKey();
      if (!key) {
        this.status = "unavailable_key";
        return;
      }
      this.status = "repairing";
      // Only renew an *already opted-in* subscription. Some iOS versions may
      // reject non-gesture subscribe(), in which case the user gets a button.
      try {
        subscription = await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: key,
        });
      } catch {
        this.status = "repair_needed";
        return;
      }
    }

    const registered = await this._syncToServer(subscription);
    if (registered) {
      this.desktopNotifications.setIsEnabledPush(true);
    }
    this.status = registered ? "ready" : "error";
  }

  async check({ force = false, allowRepair = true } = {}) {
    if (this._inFlight) {
      return this._inFlight;
    }
    if (!force && Date.now() - this._lastCheck < RECHECK_MS) {
      return;
    }
    this._lastCheck = Date.now();
    this.busy = true;
    this.testResult = null;
    this.status = "checking";
    this._inFlight = this._performCheck({ allowRepair })
      .catch(() => {
        this.status = "error";
      })
      .finally(() => {
        this.busy = false;
        this._inFlight = null;
      });
    return this._inFlight;
  }

  @action
  async connect() {
    if (this.busy || !this.supported || !this.currentUser) {
      return;
    }
    this.busy = true;
    this.status = "checking";
    this.testResult = null;
    try {
      // requestPermission must run inside the real click handler (iOS gesture).
      if (Notification.permission === "default") {
        await Notification.requestPermission();
      }
      if (Notification.permission !== "granted") {
        this.status = Notification.permission === "denied" ? "denied" : "not_enabled";
        return;
      }
      const key = this._vapidKey();
      if (!key) {
        this.status = "unavailable_key";
        return;
      }
      const registration = await this._registration();
      if (!registration?.pushManager) {
        this.status = "no_worker";
        return;
      }
      let subscription = await registration.pushManager.getSubscription();
      if (!subscription) {
        subscription = await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: key,
        });
      }
      const registered = await this._syncToServer(subscription);
      if (registered) {
        this.desktopNotifications.setIsEnabledPush(true);
      }
      this.status = registered ? "ready" : "error";
    } catch {
      this.status = "error";
    } finally {
      this._lastCheck = Date.now();
      this.busy = false;
    }
  }

  @action
  async verify() {
    this._lastCheck = 0;
    await this.check({ force: true });
  }

  @action
  async sendTest() {
    if (!this.canTest) {
      return;
    }
    this.busy = true;
    this.testResult = null;
    try {
      const registration = await this._registration();
      const subscription = await registration?.pushManager?.getSubscription();
      if (!subscription) {
        this.status = "repair_needed";
        return;
      }
      const result = await ajax("/reliable-push/test", {
        type: "POST",
        data: { subscription: subscription.toJSON() },
      });
      this.testResult = result.queued
        ? "discourse_reliable_push.test_queued"
        : "discourse_reliable_push.test_failed";
    } catch {
      this.testResult = "discourse_reliable_push.test_failed";
    } finally {
      this.busy = false;
    }
  }
}
