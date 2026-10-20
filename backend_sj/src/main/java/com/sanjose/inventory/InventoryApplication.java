package com.sanjose.inventory;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.scheduling.annotation.EnableAsync;
import org.springframework.scheduling.annotation.EnableScheduling;

import java.util.Map;

@EnableAsync
@EnableScheduling
@SpringBootApplication
public class InventoryApplication {

	public static void main(String[] args) {
		SpringApplication app = new SpringApplication(InventoryApplication.class);
		// Set here rather than in application.properties, which is gitignored and so never reaches
		// Render. The full asset list is ~1.7 MB of JSON and gzips to ~95 KB. Defaults are the lowest
		// precedence, so a property or env var can still turn it off.
		app.setDefaultProperties(Map.of(
			"server.compression.enabled", "true",
			"server.compression.mime-types", "application/json,text/html,text/plain,text/css,application/javascript"
		));
		app.run(args);
	}

}
