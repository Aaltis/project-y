package fi.breakwaterworks;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;

import com.fasterxml.jackson.databind.ObjectMapper;

public class NotesController {
	
    private final ObjectMapper objectMapper;
    
    public NotesController(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    @PostMapping("/create")
    public ResponseEntity<String> createMessage(@RequestBody NoteMessage notemessage, @AuthenticationPrincipal Jwt principal) {
        try {
            // Extract user information from the token
            String username = principal.getClaimAsString("preferred_username");  // Get the username or any other claim from the JWT
            
            // Optionally, log the username or use it to associate the note with the user
            System.out.println("User: " + username);

            // Convert the log message to a string (JSON)
            String messageJson = objectMapper.writeValueAsString(notemessage);

            return ResponseEntity.ok("Message created by user: " + username);
        } catch (Exception e) {
            // Return error response if something goes wrong
            return new ResponseEntity<>("Error sending message: " + e.getMessage(), HttpStatus.INTERNAL_SERVER_ERROR);
        }
    }
}