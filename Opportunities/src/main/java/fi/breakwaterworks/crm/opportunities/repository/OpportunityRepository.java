package fi.breakwaterworks.crm.opportunities.repository;

import fi.breakwaterworks.crm.opportunities.model.Opportunity;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.JpaSpecificationExecutor;

import java.util.UUID;

public interface OpportunityRepository extends JpaRepository<Opportunity, UUID>,
        JpaSpecificationExecutor<Opportunity> {
    Page<Opportunity> findByAccountId(UUID accountId, Pageable pageable);
    Page<Opportunity> findByOwnerId(String ownerId, Pageable pageable);
}
