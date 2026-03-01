package fi.breakwaterworks.crm.projects.repository;

import fi.breakwaterworks.crm.projects.model.WbsItem;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface WbsItemRepository extends JpaRepository<WbsItem, UUID> {
    List<WbsItem> findByProjectId(UUID projectId);
}
