CREATE TABLE wbs_item (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id  UUID         NOT NULL REFERENCES project(id),
    parent_id   UUID         REFERENCES wbs_item(id),
    name        VARCHAR(255) NOT NULL,
    description TEXT,
    wbs_code    VARCHAR(50)
);

CREATE TABLE schedule_task (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id   UUID         NOT NULL REFERENCES project(id),
    wbs_item_id  UUID         REFERENCES wbs_item(id),
    name         VARCHAR(255) NOT NULL,
    start_date   DATE,
    end_date     DATE,
    assignee_id  VARCHAR(255),
    status       VARCHAR(20)  NOT NULL DEFAULT 'TODO'
);

CREATE TABLE cost_item (
    id           UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id   UUID         NOT NULL REFERENCES project(id),
    wbs_item_id  UUID         REFERENCES wbs_item(id),
    category     VARCHAR(100),
    planned_cost NUMERIC(19,2),
    actual_cost  NUMERIC(19,2)
);

CREATE TABLE risk (
    id          UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id  UUID         NOT NULL REFERENCES project(id),
    description TEXT         NOT NULL,
    probability VARCHAR(20),
    impact      VARCHAR(20),
    response    TEXT,
    owner_id    VARCHAR(255),
    status      VARCHAR(20)  NOT NULL DEFAULT 'OPEN'
);

CREATE TABLE quality_checklist (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID         NOT NULL REFERENCES project(id),
    name       VARCHAR(255) NOT NULL
);

CREATE TABLE quality_checklist_item (
    id           UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    checklist_id UUID    NOT NULL REFERENCES quality_checklist(id),
    description  TEXT    NOT NULL,
    checked      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE comms_plan (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID         NOT NULL REFERENCES project(id),
    audience   VARCHAR(255),
    cadence    VARCHAR(100),
    channel    VARCHAR(100)
);

CREATE TABLE procurement_item (
    id         UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID          NOT NULL REFERENCES project(id),
    item       VARCHAR(255)  NOT NULL,
    vendor     VARCHAR(255),
    estimate   NUMERIC(19,2),
    status     VARCHAR(50)
);

CREATE TABLE baseline_set (
    id                UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id        UUID    NOT NULL REFERENCES project(id),
    version           INTEGER NOT NULL,
    scope_snapshot    TEXT,
    schedule_snapshot TEXT,
    cost_snapshot     TEXT,
    status            VARCHAR(20) NOT NULL DEFAULT 'DRAFT',
    created_by        VARCHAR(255) NOT NULL,
    created_at        TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now(),
    UNIQUE (project_id, version)
);
