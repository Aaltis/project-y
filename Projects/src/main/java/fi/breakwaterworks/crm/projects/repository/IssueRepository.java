package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.Issue;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface IssueRepository extends JpaRepository<Issue, UUID> {
    List<Issue> findByProjectId(UUID projectId);
}
