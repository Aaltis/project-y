package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.ScheduleTask;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface ScheduleTaskRepository extends JpaRepository<ScheduleTask, UUID> {
    List<ScheduleTask> findByProjectId(UUID projectId);
}
