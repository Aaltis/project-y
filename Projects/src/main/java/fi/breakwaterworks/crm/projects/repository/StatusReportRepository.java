package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.StatusReport;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface StatusReportRepository extends JpaRepository<StatusReport, UUID> {
    List<StatusReport> findByProjectIdOrderByPeriodStartDesc(UUID projectId);
}
