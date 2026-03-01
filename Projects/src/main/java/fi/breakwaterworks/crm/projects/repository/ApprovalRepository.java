package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.Approval;
import fi.breakwaterworks.crm.projects.model.ApprovalResourceType;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface ApprovalRepository extends JpaRepository<Approval, UUID> {
    List<Approval> findByResourceTypeAndResourceId(ApprovalResourceType resourceType, UUID resourceId);
}
