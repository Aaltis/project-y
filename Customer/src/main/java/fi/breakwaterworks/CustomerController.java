package fi.breakwaterworks;
import org.keycloak.KeycloakPrincipal;
import org.keycloak.adapters.springsecurity.token.KeycloakAuthenticationToken;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

import java.security.Principal;

@RestController
@RequestMapping("/api/customers")
public class CustomerController {

    private final CustomerRepository customerRepository;

    public CustomerController(CustomerRepository customerRepository) {
        this.customerRepository = customerRepository;
    }

    // 🔹 Endpoint to create a customer (Only logged-in users)
    @PostMapping("/create")
    public ResponseEntity<?> createCustomer(@RequestBody Customer customer, Principal principal) {
        String username = getLoggedInUsername(principal);
        customer.setCreatedBy(username);
        return ResponseEntity.ok(customerRepository.save(customer));
    }

    // 🔹 Endpoint to edit a customer (Only the creator or boss-credential)
    @PutMapping("/edit/{id}")
    public ResponseEntity<?> editCustomer(@PathVariable Long id, @RequestBody Customer updatedCustomer, Principal principal) {
        String username = getLoggedInUsername(principal);
        boolean isBoss = hasRole("boss-credential");

        return customerRepository.findById(id)
            .map(existingCustomer -> {
                if (existingCustomer.getCreatedBy().equals(username) || isBoss) {
                    existingCustomer.setName(updatedCustomer.getName());
                    existingCustomer.setEmail(updatedCustomer.getEmail());
                    return ResponseEntity.ok(customerRepository.save(existingCustomer));
                } else {
                    return ResponseEntity.status(403).body("You are not authorized to edit this customer");
                }
            })
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Customer not found"));

    }

    private String getLoggedInUsername(Principal principal) {
        if (principal instanceof Jwt jwtPrincipal) {
            return jwtPrincipal.getClaim("preferred_username");
        } else if (principal instanceof KeycloakAuthenticationToken keycloakToken) {
            return ((KeycloakPrincipal<?>) keycloakToken.getPrincipal()).getName();
        }
        return null;
    }

    private boolean hasRole(String role) {
        return SecurityContextHolder.getContext().getAuthentication()
            .getAuthorities()
            .stream()
            .anyMatch(authority -> authority.getAuthority().equals("ROLE_" + role));
    }
}
