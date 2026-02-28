package fi.breakwaterworks.crm.accounts.repository;

import fi.breakwaterworks.crm.accounts.model.Account;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.UUID;

public interface AccountRepository extends JpaRepository<Account, UUID> {
    Page<Account> findByOwnerIdAndNameContainingIgnoreCase(String ownerId, String search, Pageable pageable);
    Page<Account> findByNameContainingIgnoreCase(String search, Pageable pageable);
}
