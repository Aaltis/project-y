package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.ProjectRole;
import fi.breakwaterworks.crm.projects.model.ProjectRoleAssignment;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface ProjectRoleAssignmentRepository extends JpaRepository<ProjectRoleAssignment, UUID> {

    List<ProjectRoleAssignment> findByProjectId(UUID projectId);

    boolean existsByProjectIdAndUserId(UUID projectId, String userId);

    boolean existsByProjectIdAndUserIdAndRole(UUID projectId, String userId, ProjectRole role);
}
