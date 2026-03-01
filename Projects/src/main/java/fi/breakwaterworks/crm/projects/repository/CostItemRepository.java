package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.CostItem;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface CostItemRepository extends JpaRepository<CostItem, UUID> {
    List<CostItem> findByProjectId(UUID projectId);
}
