package fi.breakwaterworks.crm.diagrams.repository;

import fi.breakwaterworks.crm.diagrams.model.DiagramEdge;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface DiagramEdgeRepository extends JpaRepository<DiagramEdge, UUID> {
    List<DiagramEdge> findByDiagramId(UUID diagramId);
    void deleteByDiagramId(UUID diagramId);
}
