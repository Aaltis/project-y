package fi.breakwaterworks.crm.accounts.service;

import fi.breakwaterworks.crm.accounts.repository.AccountRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service("perm")
@RequiredArgsConstructor
public class PermissionService {

    private final AccountRepository accountRepository;

    public boolean canAccess(UUID id, Authentication auth) {
        if (isAdmin(auth)) return true;
        String sub = sub(auth);
        return accountRepository.findById(id)
                .map(a -> a.getOwnerId().equals(sub))
                .orElse(false);
    }

    private boolean isAdmin(Authentication auth) {
        return auth.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_crm_admin"));
    }

    private String sub(Authentication auth) {
        if (auth.getPrincipal() instanceof Jwt jwt) {
            return jwt.getSubject();
        }
        return auth.getName();
    }
}
