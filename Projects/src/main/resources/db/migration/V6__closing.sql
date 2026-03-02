-- Phase 7.7 — Closing
-- closure_report: PM drafts → submits → Sponsor approves → project can be CLOSED
-- lessons_learned: captured anytime during closing phase

CREATE TABLE closure_report (
    id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id         UUID        NOT NULL REFERENCES project(id),
    outcomes_summary   TEXT,
    budget_actual      NUMERIC(19,2),
    schedule_actual    TEXT,
    acceptance_summary TEXT,
    status             VARCHAR(20) NOT NULL DEFAULT 'DRAFT'
    -- status: DRAFT → SUBMITTED → APPROVED
);

CREATE TABLE lessons_learned (
    id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id     UUID        NOT NULL REFERENCES project(id),
    category       VARCHAR(100),
    what_happened  TEXT        NOT NULL,
    recommendation TEXT,
    created_by     VARCHAR(255) NOT NULL,
    created_at     TIMESTAMP   NOT NULL DEFAULT now()
);
