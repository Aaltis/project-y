package fi.breakwaterworks.crm.diagrams.repository;

import fi.breakwaterworks.crm.diagrams.model.DiagramNode;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface DiagramNodeRepository extends JpaRepository<DiagramNode, UUID> {
    List<DiagramNode> findByDiagramId(UUID diagramId);
    void deleteByDiagramId(UUID diagramId);
}
