package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.WorkLog;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.UUID;

public interface WorkLogRepository extends JpaRepository<WorkLog, UUID> {

    List<WorkLog> findByTaskId(UUID taskId);

    @Query("SELECT w FROM WorkLog w WHERE w.taskId IN " +
           "(SELECT t.id FROM ScheduleTask t WHERE t.projectId = :projectId)")
    List<WorkLog> findByProjectId(@Param("projectId") UUID projectId);
}
