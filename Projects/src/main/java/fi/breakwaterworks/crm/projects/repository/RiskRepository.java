package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.Risk;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface RiskRepository extends JpaRepository<Risk, UUID> {
    List<Risk> findByProjectId(UUID projectId);
}
