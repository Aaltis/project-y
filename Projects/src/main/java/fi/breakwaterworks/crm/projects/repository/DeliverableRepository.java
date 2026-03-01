package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.Deliverable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface DeliverableRepository extends JpaRepository<Deliverable, UUID> {
    List<Deliverable> findByProjectId(UUID projectId);
}
