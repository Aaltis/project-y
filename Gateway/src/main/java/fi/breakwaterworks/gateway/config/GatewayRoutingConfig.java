package fi.breakwaterworks.gateway.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.gateway.route.RouteLocator;
import org.springframework.cloud.gateway.route.builder.RouteLocatorBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class GatewayRoutingConfig {

    @Value("${gateway.routes.keycloak-uri}")
    private String keycloakUri;

    @Value("${gateway.routes.customer-uri}")
    private String customerUri;

    @Value("${gateway.routes.accounts-uri}")
    private String accountsUri;

    @Value("${gateway.routes.contacts-uri}")
    private String contactsUri;

    @Value("${gateway.routes.opportunities-uri}")
    private String opportunitiesUri;

    @Value("${gateway.routes.activities-uri}")
    private String activitiesUri;

    @Value("${gateway.routes.projects-uri}")
    private String projectsUri;

    @Bean
    public RouteLocator routes(RouteLocatorBuilder builder) {
        return builder.routes()
            // /auth/** passes through to Keycloak — no logging, no rate limiting
            .route("keycloak", r -> r
                .path("/auth/**")
                .uri(keycloakUri))
            // Nested resource routes must come BEFORE their parent service routes
            // so that /api/accounts/{id}/contacts is not swallowed by /api/accounts/**
            .route("contacts-nested", r -> r
                .path("/api/accounts/*/contacts", "/api/accounts/*/contacts/**")
                .uri(contactsUri))
            .route("activities-nested", r -> r
                .path("/api/opportunities/*/activities", "/api/opportunities/*/activities/**")
                .uri(activitiesUri))
            // Top-level CRM service routes
            .route("accounts", r -> r
                .path("/api/accounts", "/api/accounts/**")
                .uri(accountsUri))
            .route("contacts", r -> r
                .path("/api/contacts", "/api/contacts/**")
                .uri(contactsUri))
            .route("opportunities", r -> r
                .path("/api/opportunities", "/api/opportunities/**")
                .uri(opportunitiesUri))
            .route("activities", r -> r
                .path("/api/activities", "/api/activities/**")
                .uri(activitiesUri))
            // PMBOK Projects service
            .route("projects", r -> r
                .path("/api/projects", "/api/projects/**")
                .uri(projectsUri))
            // Fallback: remaining /api/** goes to legacy Customer service
            .route("customer", r -> r
                .path("/api/**")
                .uri(customerUri))
            .build();
    }
}
