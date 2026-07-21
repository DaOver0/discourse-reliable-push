(function () {
  function sendAck(url) {
    if (!url) {
      return Promise.resolve();
    }

    return fetch(url, {
      method: "POST",
      credentials: "same-origin",
      keepalive: true,
    }).catch(function (error) {
      console.error("Reliable Push acknowledgement failed", error);
    });
  }

  self.addEventListener("push", function (event) {
    var payload;
    try {
      payload = event.data && event.data.json();
    } catch (_error) {
      return;
    }

    var ack = payload && payload.reliable_push;
    if (ack && ack.received_url) {
      event.waitUntil(sendAck(ack.received_url));
    }
  });

  self.addEventListener("notificationclick", function (event) {
    var actionData = event.notification && event.notification.data && event.notification.data.actionData;
    var ack = actionData && actionData.reliable_push;
    if (ack && ack.opened_url) {
      event.waitUntil(sendAck(ack.opened_url));
    }
  });
})();
