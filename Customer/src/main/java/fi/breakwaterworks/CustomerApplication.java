package fi.breakwaterworks;

import java.util.Map;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.context.event.ApplicationReadyEvent;

@SpringBootApplication
public class CustomerApplication {

	public static void main(String[] args) {
		// Print environment variables at startup
		SpringApplication app = new SpringApplication(CustomerApplication.class);
		app.addListeners((event) -> {
			if (event instanceof ApplicationReadyEvent) {
				System.out.println("=== ENVIRONMENT VARIABLES ===");
				System.getenv().forEach((key, value) -> System.out.println(key + ": " + value));
			}
		});
		app.run(args);
	}
}
