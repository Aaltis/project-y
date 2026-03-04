CREATE INDEX IF NOT EXISTS idx_opportunity_owner_id   ON opportunity (owner_id);
CREATE INDEX IF NOT EXISTS idx_opportunity_account_id ON opportunity (account_id);
CREATE INDEX IF NOT EXISTS idx_opportunity_stage      ON opportunity (stage);
