CREATE TABLE deliverable (
    id                  UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id          UUID         NOT NULL REFERENCES project(id),
    name                VARCHAR(255) NOT NULL,
    due_date            DATE,
    acceptance_criteria TEXT,
    status              VARCHAR(20)  NOT NULL DEFAULT 'PLANNED',
    submitted_by        VARCHAR(255)
);

CREATE TABLE work_log (
    id       UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id  UUID         NOT NULL REFERENCES schedule_task(id),
    user_id  VARCHAR(255) NOT NULL,
    log_date DATE         NOT NULL,
    hours    NUMERIC(5,2) NOT NULL,
    note     TEXT
);

CREATE TABLE issue (
    id         UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID         NOT NULL REFERENCES project(id),
    title      VARCHAR(255) NOT NULL,
    severity   VARCHAR(20)  NOT NULL DEFAULT 'MEDIUM',
    owner_id   VARCHAR(255),
    status     VARCHAR(20)  NOT NULL DEFAULT 'OPEN'
);
