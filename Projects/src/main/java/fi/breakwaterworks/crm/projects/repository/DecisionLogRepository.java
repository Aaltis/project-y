package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.DecisionLog;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface DecisionLogRepository extends JpaRepository<DecisionLog, UUID> {
    List<DecisionLog> findByProjectId(UUID projectId);
}
