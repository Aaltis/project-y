package fi.breakwaterworks.crm.contacts.repository;

import fi.breakwaterworks.crm.contacts.model.Contact;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.UUID;

public interface ContactRepository extends JpaRepository<Contact, UUID> {
    List<Contact> findByAccountId(UUID accountId);
}
