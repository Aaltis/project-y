package fi.breakwaterworks.crm.accounts.controller;

import fi.breakwaterworks.crm.accounts.model.Account;
import fi.breakwaterworks.crm.accounts.repository.AccountRepository;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.ResponseEntity;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/api/accounts")
@RequiredArgsConstructor
public class AccountController {

    private final AccountRepository accountRepository;

    @GetMapping
    public Page<Account> list(
            @RequestParam(defaultValue = "") String search,
            @PageableDefault(size = 20) Pageable pageable,
            Authentication auth) {
        boolean isAdmin = auth.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_crm_admin"));
        if (isAdmin) {
            return accountRepository.findByNameContainingIgnoreCase(search, pageable);
        }
        return accountRepository.findByOwnerIdAndNameContainingIgnoreCase(sub(auth), search, pageable);
    }

    @PostMapping
    public ResponseEntity<Account> create(@Valid @RequestBody Account account, Authentication auth) {
        account.setOwnerId(sub(auth));
        return ResponseEntity.ok(accountRepository.save(account));
    }

    @GetMapping("/{id}")
    @PreAuthorize("@perm.canAccess(#id, authentication)")
    public ResponseEntity<Account> get(@PathVariable UUID id) {
        return accountRepository.findById(id)
                .map(ResponseEntity::ok)
                .orElse(ResponseEntity.notFound().build());
    }

    @PutMapping("/{id}")
    @PreAuthorize("@perm.canAccess(#id, authentication)")
    public ResponseEntity<Account> update(@PathVariable UUID id, @Valid @RequestBody Account body) {
        return accountRepository.findById(id).map(existing -> {
            existing.setName(body.getName());
            return ResponseEntity.ok(accountRepository.save(existing));
        }).orElse(ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    @PreAuthorize("@perm.canAccess(#id, authentication)")
    public ResponseEntity<Void> delete(@PathVariable UUID id) {
        if (!accountRepository.existsById(id)) return ResponseEntity.notFound().build();
        accountRepository.deleteById(id);
        return ResponseEntity.noContent().build();
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) {
            return jwt.getSubject();
        }
        return auth.getName();
    }
}
