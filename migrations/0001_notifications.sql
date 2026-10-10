-- Notifications cell: notification rules and the notification log (what was
-- queued for which task snapshot, and whether a channel delivered it). Every
-- row belongs to a workspace and is visible only while bound to it.

CREATE SCHEMA notifications;

CREATE FUNCTION notifications.current_workspace() RETURNS uuid
LANGUAGE sql STABLE AS $$
    SELECT nullif(current_setting('app.workspace_id', true), '')::uuid
$$;

CREATE TABLE notifications.rules (
    workspace_id           uuid NOT NULL,
    id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    legacy_id              bigint,
    name                   text NOT NULL CHECK (length(name) BETWEEN 1 AND 200),
    description            text,
    rule_type              text NOT NULL CHECK (rule_type IN (
        'overdue', 'due_soon', 'high_priority', 'stale', 'blocked', 'status_change', 'reminder')),
    config                 jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(config) = 'object'),
    channels               jsonb NOT NULL DEFAULT '["console"]'::jsonb CHECK (jsonb_typeof(channels) = 'array'),
    project_filter         text,
    category_filter        text,
    priority_filter        integer,
    status_filter          jsonb CHECK (status_filter IS NULL OR jsonb_typeof(status_filter) = 'array'),
    check_interval_minutes integer NOT NULL DEFAULT 60 CHECK (check_interval_minutes > 0),
    last_checked_at        timestamptz,
    last_triggered_at      timestamptz,
    is_active              boolean NOT NULL DEFAULT true,
    version                bigint NOT NULL DEFAULT 1,
    created_at             timestamptz NOT NULL DEFAULT now(),
    updated_at             timestamptz NOT NULL DEFAULT now(),
    UNIQUE (workspace_id, id)
);
CREATE UNIQUE INDEX rules_legacy ON notifications.rules (workspace_id, legacy_id) WHERE legacy_id IS NOT NULL;

CREATE TABLE notifications.log (
    workspace_id      uuid NOT NULL,
    id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    legacy_id         bigint,
    rule_id           bigint,
    task_id           bigint,
    title             text NOT NULL CHECK (length(title) BETWEEN 1 AND 500),
    message           text NOT NULL CHECK (length(message) BETWEEN 1 AND 8000),
    notification_type text NOT NULL CHECK (notification_type ~ '^[a-z][a-z0-9_]{0,59}$'),
    severity          text NOT NULL DEFAULT 'info' CHECK (severity IN ('info', 'warning', 'critical', 'success')),
    channel           text NOT NULL DEFAULT 'console',
    task_title        text,
    task_status       text,
    task_priority     integer,
    task_due_date     text,
    task_project      text,
    metadata          jsonb CHECK (metadata IS NULL OR jsonb_typeof(metadata) = 'object'),
    -- A caller-chosen key that makes queueing idempotent (e.g. one per task snapshot per day).
    dedupe_key        text CHECK (dedupe_key IS NULL OR length(dedupe_key) BETWEEN 8 AND 200),
    sent_at           timestamptz NOT NULL DEFAULT now(),
    read_at           timestamptz,
    dismissed_at      timestamptz,
    delivered_at      timestamptz,
    delivery_channel  text,
    delivery_error    text,
    delivery_attempts integer NOT NULL DEFAULT 0 CHECK (delivery_attempts >= 0),
    version           bigint NOT NULL DEFAULT 1,
    UNIQUE (workspace_id, id),
    FOREIGN KEY (workspace_id, rule_id) REFERENCES notifications.rules (workspace_id, id) ON DELETE SET NULL (rule_id)
);
CREATE UNIQUE INDEX log_dedupe ON notifications.log (workspace_id, dedupe_key) WHERE dedupe_key IS NOT NULL;
CREATE INDEX log_type_sent ON notifications.log (workspace_id, notification_type, sent_at DESC);
CREATE INDEX log_pending ON notifications.log (workspace_id, notification_type) WHERE delivered_at IS NULL;
CREATE INDEX log_task ON notifications.log (workspace_id, task_id);

DO $$
DECLARE
    t text;
BEGIN
    FOREACH t IN ARRAY ARRAY['rules', 'log'] LOOP
        EXECUTE format('ALTER TABLE notifications.%I ENABLE ROW LEVEL SECURITY', t);
        EXECUTE format('ALTER TABLE notifications.%I FORCE ROW LEVEL SECURITY', t);
        EXECUTE format('CREATE POLICY workspace_isolation ON notifications.%I'
                       ' USING (workspace_id = notifications.current_workspace())'
                       ' WITH CHECK (workspace_id = notifications.current_workspace())', t);
    END LOOP;
END
$$;

GRANT USAGE ON SCHEMA notifications TO notifications_api;
GRANT EXECUTE ON FUNCTION notifications.current_workspace() TO notifications_api;
GRANT SELECT, INSERT, UPDATE ON notifications.rules, notifications.log TO notifications_api;
