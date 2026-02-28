package fi.breakwaterworks;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;
import org.springframework.http.HttpStatus;

@RestController
@RequestMapping("/api/customers")
public class CustomerController {

    private final CustomerRepository customerRepository;

    public CustomerController(CustomerRepository customerRepository) {
        this.customerRepository = customerRepository;
    }

    @PostMapping("/create")
    public ResponseEntity<?> createCustomer(@RequestBody Customer customer, @AuthenticationPrincipal Jwt jwt) {
        String username = jwt != null ? jwt.getClaimAsString("preferred_username") : null;
        customer.setCreatedBy(username);
        return ResponseEntity.ok(customerRepository.save(customer));
    }

    @PutMapping("/edit/{id}")
    public ResponseEntity<?> editCustomer(@PathVariable Long id, @RequestBody Customer updatedCustomer, @AuthenticationPrincipal Jwt jwt) {
        String username = jwt != null ? jwt.getClaimAsString("preferred_username") : null;
        boolean isBoss = hasRole("boss-credential");

        return customerRepository.findById(id)
            .map(existingCustomer -> {
                if (username != null && username.equals(existingCustomer.getCreatedBy()) || isBoss) {
                    existingCustomer.setName(updatedCustomer.getName());
                    existingCustomer.setEmail(updatedCustomer.getEmail());
                    return ResponseEntity.ok(customerRepository.save(existingCustomer));
                } else {
                    return ResponseEntity.status(403).body("You are not authorized to edit this customer");
                }
            })
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Customer not found"));
    }

    private boolean hasRole(String role) {
        return SecurityContextHolder.getContext().getAuthentication()
            .getAuthorities()
            .stream()
            .anyMatch(authority -> authority.getAuthority().equals("ROLE_" + role));
    }
}
