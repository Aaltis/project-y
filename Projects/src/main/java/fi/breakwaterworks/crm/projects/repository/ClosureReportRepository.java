package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.ClosureReport;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;
import java.util.UUID;

public interface ClosureReportRepository extends JpaRepository<ClosureReport, UUID> {
    Optional<ClosureReport> findByProjectId(UUID projectId);
}
