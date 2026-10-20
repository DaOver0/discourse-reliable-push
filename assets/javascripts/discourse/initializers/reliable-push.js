// Never replace core's Forum/Chat push pipeline; only validate its subscriptions.
export default {
  name: "discourse-reliable-push",
  initialize(container) {
    const service = container.lookup("service:reliable-push");
    service?.start();
  },
};
