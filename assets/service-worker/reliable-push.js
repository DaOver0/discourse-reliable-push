(function () {
  function sendAck(url, token) {
    if (!url || !token) {
      return Promise.resolve();
    }

    return fetch(url, {
      method: "POST",
      credentials: "same-origin",
      keepalive: true,
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: token }),
    }).catch(function (error) {
      console.error("Reliable Push acknowledgement failed", error);
    });
  }

  function metadataFromPush(payload) {
    if (!payload) {
      return null;
    }

    return (
      payload.reliable_push ||
      (payload.data && payload.data.reliable_push) ||
      (payload.data &&
        payload.data.actionData &&
        payload.data.actionData.reliablePush) ||
      null
    );
  }

  function metadataFromNotification(notification) {
    var data = notification && notification.data;
    if (!data) {
      return null;
    }

    return (
      data.reliable_push ||
      (data.actionData && data.actionData.reliablePush) ||
      (data.action_data && data.action_data.reliable_push) ||
      null
    );
  }

  self.addEventListener("push", function (event) {
    var payload;
    try {
      payload = event.data && event.data.json();
    } catch (_error) {
      return;
    }

    var metadata = metadataFromPush(payload);
    if (metadata) {
      event.waitUntil(sendAck(metadata.received_url, metadata.token));
    }
  });

  self.addEventListener("notificationclick", function (event) {
    var metadata = metadataFromNotification(event.notification);
    if (metadata) {
      event.waitUntil(sendAck(metadata.opened_url, metadata.token));
    }
  });
})();
