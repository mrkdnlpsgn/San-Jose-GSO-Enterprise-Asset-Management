package com.sanjose.inventory;

import com.sanjose.inventory.entity.Office;
import com.sanjose.inventory.entity.User;
import com.sanjose.inventory.repository.OfficeRepository;
import com.sanjose.inventory.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.util.List;

@Component
@RequiredArgsConstructor
@Slf4j
public class DataInitializer implements CommandLineRunner {

    private final UserRepository userRepository;
    private final OfficeRepository officeRepository;
    private final PasswordEncoder passwordEncoder;
    private final org.springframework.jdbc.core.JdbcTemplate jdbcTemplate;

    private static final List<String> DEFAULT_OFFICES = List.of(
        "Office of the Mayor",
        "Office of the Vice Mayor",
        "Sangguniang Bayan Office",
        "Human Resource Management Office",
        "Budget Office",
        "Accounting Office",
        "Treasury Office",
        "Assessor's Office",
        "Civil Registrar's Office",
        "Municipal Engineering Office",
        "Municipal Planning and Development Office",
        "Municipal Health Office",
        "Municipal Social Welfare and Development Office",
        "Municipal Agriculture Office",
        "General Services Office",
        "Information and Communications Technology Office",
        "Disaster Risk Reduction and Management Office"
    );

    @Override
    public void run(String... args) {
        log.info("DataInitializer: seeding default accounts...");
        seedUser("admin", "admin123", "Administrator", "ADMIN", "admin@sanjosegso.local");
        seedUser("ict_staff", "ict2024", "ICT Officer", "STAFF", "ict.staff@sanjosegso.local");

        log.info("DataInitializer: seeding default offices...");
        DEFAULT_OFFICES.forEach(this::seedOffice);

        // every account (seeded ones included) needs its personnel record — see sp_personnel_sync_accounts
        jdbcTemplate.update("CALL sp_personnel_sync_accounts()");

        log.info("DataInitializer: done.");
    }

    private void seedUser(String username, String password, String fullName, String role, String email) {
        userRepository.findByUsernameIgnoreCase(username).ifPresentOrElse(
            existing -> {
                existing.setFullName(fullName);
                existing.setPassword(passwordEncoder.encode(password));
                existing.setRole(role);
                existing.setFailedLoginAttempts(0);
                existing.setAccountLockedUntil(null);
                existing.setIsActive(true);
                // these are known fixture credentials, not a real temp password — never force a change
                existing.setMustChangePassword(false);
                if (existing.getEmail() == null) existing.setEmail(email);
                userRepository.saveAndFlush(existing);
                log.info("  reset: {}", username);
            },
            () -> {
                userRepository.saveAndFlush(User.builder()
                    .username(username)
                    .password(passwordEncoder.encode(password))
                    .fullName(fullName)
                    .role(role)
                    .email(email)
                    .isActive(true)
                    .mustChangePassword(false)
                    .build());
                log.info("  seeded: {}", username);
            }
        );
    }

    private void seedOffice(String name) {
        if (!officeRepository.existsByOfficeName(name)) {
            officeRepository.saveAndFlush(Office.builder().officeName(name).build());
            log.info("  office seeded: {}", name);
        }
    }
}
