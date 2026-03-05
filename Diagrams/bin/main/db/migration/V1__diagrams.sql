CREATE TABLE IF NOT EXISTS diagram (
    id         UUID PRIMARY KEY,
    name       VARCHAR(255) NOT NULL,
    owner_id   VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now(),
    updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS diagram_node (
    id          UUID PRIMARY KEY,
    diagram_id  UUID NOT NULL REFERENCES diagram(id) ON DELETE CASCADE,
    node_key    VARCHAR(100) NOT NULL,
    entity_type VARCHAR(50),
    entity_id   UUID,
    label       VARCHAR(255),
    x           DOUBLE PRECISION NOT NULL DEFAULT 0,
    y           DOUBLE PRECISION NOT NULL DEFAULT 0,
    color       VARCHAR(20),
    shape       VARCHAR(20) NOT NULL DEFAULT 'RECTANGLE',
    UNIQUE (diagram_id, node_key)
);

CREATE TABLE IF NOT EXISTS diagram_edge (
    id         UUID PRIMARY KEY,
    diagram_id UUID NOT NULL REFERENCES diagram(id) ON DELETE CASCADE,
    source_key VARCHAR(100) NOT NULL,
    target_key VARCHAR(100) NOT NULL,
    label      VARCHAR(255),
    style      VARCHAR(20) NOT NULL DEFAULT 'SOLID'
);

CREATE INDEX IF NOT EXISTS idx_diagram_owner_id ON diagram (owner_id);
CREATE INDEX IF NOT EXISTS idx_diagram_node_diagram_id ON diagram_node (diagram_id);
CREATE INDEX IF NOT EXISTS idx_diagram_edge_diagram_id ON diagram_edge (diagram_id);
