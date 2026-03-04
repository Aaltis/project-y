package fi.breakwaterworks.crm.diagrams.model;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.UuidGenerator;

import java.util.UUID;

@Entity
@Table(name = "diagram_node")
@Data
public class DiagramNode {

    @Id
    @UuidGenerator
    private UUID id;

    @Column(name = "diagram_id", nullable = false)
    private UUID diagramId;

    @Column(name = "node_key", nullable = false)
    private String nodeKey;

    @Column(name = "entity_type")
    private String entityType;

    @Column(name = "entity_id")
    private UUID entityId;

    private String label;

    @Column(nullable = false)
    private Double x = 0.0;

    @Column(nullable = false)
    private Double y = 0.0;

    private String color;

    @Column(nullable = false)
    private String shape = "RECTANGLE";
}
