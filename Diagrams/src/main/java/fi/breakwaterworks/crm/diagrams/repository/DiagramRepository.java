package fi.breakwaterworks.crm.diagrams.repository;

import fi.breakwaterworks.crm.diagrams.model.Diagram;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface DiagramRepository extends JpaRepository<Diagram, UUID> {
    List<Diagram> findByOwnerId(String ownerId);
}
