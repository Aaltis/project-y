-- Add change_request_id linkage to baseline_set
ALTER TABLE baseline_set
    ADD COLUMN change_request_id UUID;

CREATE TABLE change_request (
    id                     UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id             UUID         NOT NULL REFERENCES project(id),
    type                   VARCHAR(20)  NOT NULL,
    description            TEXT         NOT NULL,
    impact_scope           TEXT,
    impact_schedule_days   INTEGER,
    impact_cost            NUMERIC(19,2),
    submitted_by           VARCHAR(255) NOT NULL,
    status                 VARCHAR(20)  NOT NULL DEFAULT 'DRAFT',
    created_at             TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now()
);

CREATE TABLE decision_log (
    id            UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id    UUID    NOT NULL REFERENCES project(id),
    decision      TEXT    NOT NULL,
    decision_date DATE    NOT NULL,
    made_by       VARCHAR(255) NOT NULL
);

CREATE TABLE status_report (
    id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id   UUID        NOT NULL REFERENCES project(id),
    period_start DATE        NOT NULL,
    period_end   DATE        NOT NULL,
    summary      TEXT,
    rag_scope    VARCHAR(10) NOT NULL DEFAULT 'GREEN',
    rag_schedule VARCHAR(10) NOT NULL DEFAULT 'GREEN',
    rag_cost     VARCHAR(10) NOT NULL DEFAULT 'GREEN',
    key_risks    TEXT,
    key_issues   TEXT,
    created_by   VARCHAR(255) NOT NULL,
    created_at   TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now()
);
