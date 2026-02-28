package fi.breakwaterworks.crm.opportunities.service;

import fi.breakwaterworks.crm.opportunities.repository.OpportunityRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.stereotype.Service;

import java.util.UUID;

@Service("perm")
@RequiredArgsConstructor
public class PermissionService {

    private final OpportunityRepository opportunityRepository;

    public boolean canAccess(UUID id, Authentication auth) {
        if (isAdmin(auth)) return true;
        String sub = sub(auth);
        return opportunityRepository.findById(id)
                .map(o -> o.getOwnerId().equals(sub))
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
