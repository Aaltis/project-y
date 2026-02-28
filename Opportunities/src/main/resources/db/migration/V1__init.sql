CREATE TABLE IF NOT EXISTS opportunity (
    id         UUID           PRIMARY KEY,
    account_id UUID           NOT NULL,
    name       VARCHAR(255)   NOT NULL,
    amount     NUMERIC(19, 2),
    stage      VARCHAR(50)    NOT NULL DEFAULT 'PROSPECT',
    close_date DATE,
    owner_id   VARCHAR(255)   NOT NULL,
    updated_at TIMESTAMP WITHOUT TIME ZONE
);
