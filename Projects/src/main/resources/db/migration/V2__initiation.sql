CREATE TABLE project (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name         VARCHAR(255) NOT NULL,
    sponsor_id   VARCHAR(255) NOT NULL,
    pm_id        VARCHAR(255) NOT NULL,
    status       VARCHAR(20)  NOT NULL DEFAULT 'DRAFT',
    start_target DATE,
    end_target   DATE,
    created_at   TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now()
);

CREATE TABLE project_charter (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id        UUID         NOT NULL REFERENCES project(id),
    objectives        TEXT,
    high_level_scope  TEXT,
    success_criteria  TEXT,
    summary_budget    NUMERIC(19,2),
    key_risks         TEXT,
    status            VARCHAR(20)  NOT NULL DEFAULT 'DRAFT'
);

CREATE TABLE stakeholder_register (
    id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id       UUID         NOT NULL REFERENCES project(id),
    name             VARCHAR(255) NOT NULL,
    user_id          VARCHAR(255),
    influence        VARCHAR(20),
    interest         VARCHAR(20),
    engagement_level VARCHAR(50)
);

CREATE TABLE approval (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    resource_type VARCHAR(20)  NOT NULL,
    resource_id   UUID         NOT NULL,
    requested_by  VARCHAR(255) NOT NULL,
    approver_id   VARCHAR(255),
    status        VARCHAR(20)  NOT NULL DEFAULT 'PENDING',
    comment       TEXT,
    created_at    TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now()
);
