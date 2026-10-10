import { defineRailway, project, service } from "railway/iac";

// solo-notifications: the notifications cell. Variables stay unmanaged (secrets live in Railway only).
// notifications-api sleeps when idle (Railway Serverless) and wakes on the next request.
// No graph publisher: notification log entries are operational records, not graph nodes.
export default defineRailway(() => {
  const api = service("notifications-api", {
    healthcheck: "/health",
    healthcheckTimeout: 60,
    deploy: { sleepApplication: true },
  });

  return project("solo-notifications", {
    variables: { managed: false },
    resources: [api],
  });
});
