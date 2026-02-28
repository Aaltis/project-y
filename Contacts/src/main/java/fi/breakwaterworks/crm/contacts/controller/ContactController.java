package fi.breakwaterworks.crm.contacts.controller;

import fi.breakwaterworks.crm.contacts.model.Contact;
import fi.breakwaterworks.crm.contacts.repository.ContactRepository;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.UUID;

@RestController
@RequestMapping("/api/accounts/{accountId}/contacts")
@RequiredArgsConstructor
public class ContactController {

    private final ContactRepository contactRepository;

    @GetMapping
    public List<Contact> list(@PathVariable UUID accountId) {
        return contactRepository.findByAccountId(accountId);
    }

    @PostMapping
    public ResponseEntity<Contact> create(@PathVariable UUID accountId, @Valid @RequestBody Contact contact) {
        contact.setAccountId(accountId);
        return ResponseEntity.ok(contactRepository.save(contact));
    }

    @GetMapping("/{id}")
    public ResponseEntity<Contact> get(@PathVariable UUID accountId, @PathVariable UUID id) {
        return contactRepository.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PutMapping("/{id}")
    public ResponseEntity<Contact> update(@PathVariable UUID accountId, @PathVariable UUID id,
                                          @Valid @RequestBody Contact body) {
        return contactRepository.findById(id).map(existing -> {
            existing.setName(body.getName());
            existing.setEmail(body.getEmail());
            existing.setPhone(body.getPhone());
            return ResponseEntity.ok(contactRepository.save(existing));
        }).orElse(ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable UUID accountId, @PathVariable UUID id) {
        if (!contactRepository.existsById(id)) return ResponseEntity.notFound().build();
        contactRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }
}
