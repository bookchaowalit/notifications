import { defineRailway, project, service } from "railway/iac";

// notifications: the notifications cell. Variables stay unmanaged (secrets live in Railway only).
// notifications-api sleeps when idle (Railway Serverless) and wakes on the next request.
// notifications-dispatcher is a cron run that evaluates the rules against the tasks cell,
// queues what matched and delivers pending entries to Telegram, then exits.
// No graph publisher: notification log entries are operational records, not graph nodes.
export default defineRailway(() => {
  const api = service("notifications-api", {
    healthcheck: "/health",
    healthcheckTimeout: 60,
    deploy: { sleepApplication: true },
  });
  const dispatcher = service("notifications-dispatcher", {
    startCommand: "notifications-dispatch",
    deploy: { cronSchedule: "*/30 * * * *", restartPolicyType: "NEVER" },
  });

  return project("notifications", {
    variables: { managed: false },
    resources: [api, dispatcher],
  });
});
