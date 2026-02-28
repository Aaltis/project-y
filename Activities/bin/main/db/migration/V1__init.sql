CREATE TABLE IF NOT EXISTS activity (
    id             UUID PRIMARY KEY,
    opportunity_id UUID         NOT NULL,
    type           VARCHAR(50)  NOT NULL,
    text           TEXT,
    due_at         TIMESTAMP WITHOUT TIME ZONE,
    created_by     VARCHAR(255),
    created_at     TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now()
);
