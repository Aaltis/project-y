CREATE TABLE project_role_assignment (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    project_id UUID         NOT NULL,
    user_id    VARCHAR(255) NOT NULL,
    role       VARCHAR(20)  NOT NULL,
    UNIQUE (project_id, user_id, role)
);
