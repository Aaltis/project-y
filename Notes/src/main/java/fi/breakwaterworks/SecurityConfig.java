package fi.breakwaterworks;

import org.springframework.context.annotation.Bean;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.web.SecurityFilterChain;

@EnableWebSecurity
public class SecurityConfig {

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
        .	csrf(csrf -> csrf.disable())  // Disable CSRF protection for stateless API
            .authorizeHttpRequests(authorize -> authorize
                .requestMatchers("/create").authenticated()  // Protect the /create endpoint
                .anyRequest().permitAll()  // Allow other endpoints (if any)
            )
            .oauth2ResourceServer(oauth2 -> oauth2.jwt());  // Enable JWT-based OAuth2
        return http.build();
    }
}

