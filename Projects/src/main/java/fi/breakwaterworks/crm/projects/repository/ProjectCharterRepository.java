package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.ProjectCharter;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface ProjectCharterRepository extends JpaRepository<ProjectCharter, UUID> {
    Optional<ProjectCharter> findByProjectId(UUID projectId);
}
