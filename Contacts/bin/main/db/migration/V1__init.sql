CREATE TABLE IF NOT EXISTS contact (
    id         UUID PRIMARY KEY,
    account_id UUID         NOT NULL,
    name       VARCHAR(255) NOT NULL,
    email      VARCHAR(255),
    phone      VARCHAR(50)
);
