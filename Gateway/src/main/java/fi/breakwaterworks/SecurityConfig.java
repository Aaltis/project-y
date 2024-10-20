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
            .authorizeHttpRequests(authorize -> authorize
                .requestMatchers("/login**", "/oauth2/**").permitAll()  // Allow public access to login and OAuth2 endpoints
                .anyRequest().authenticated()  // Protect all other routes
            )
            .oauth2Login();  // Enable OAuth2 login using defaults
        return http.build();
    }
}
