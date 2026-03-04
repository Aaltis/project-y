package fi.breakwaterworks.crm.diagrams.model;

import jakarta.persistence.*;
import lombok.Data;
import org.hibernate.annotations.UuidGenerator;

import java.util.UUID;

@Entity
@Table(name = "diagram_edge")
@Data
public class DiagramEdge {

    @Id
    @UuidGenerator
    private UUID id;

    @Column(name = "diagram_id", nullable = false)
    private UUID diagramId;

    @Column(name = "source_key", nullable = false)
    private String sourceKey;

    @Column(name = "target_key", nullable = false)
    private String targetKey;

    private String label;

    @Column(nullable = false)
    private String style = "SOLID";
}
