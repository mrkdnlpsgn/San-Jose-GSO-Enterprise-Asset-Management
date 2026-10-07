package com.sanjose.inventory.service;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.stream.Stream;

// One profile picture per account, stored as uploads/avatars/{userId}-{random}.{ext}. The file
// name is the only record (no users column), and the random part changes on every upload so
// browsers never show a cached old picture. The web app crops and shrinks the photo to a small
// square JPEG before sending it.
@Service
public class ProfilePictureService {

    private static final String SUBDIR = "avatars";
    private static final long MAX_SIZE = 2L * 1024 * 1024;
    // HEIC is left out: browsers can't display it in an <img>
    private static final Set<String> ALLOWED = Set.of("image/jpeg", "image/png", "image/webp");

    @Value("${app.upload-dir:uploads}")
    private String uploadDir;

    // Root-relative URL like /uploads/avatars/5-ab12….jpg, or null when there is none.
    public String urlFor(Long userId) {
        List<Path> files = filesOf(userId);
        return files.isEmpty() ? null : "/uploads/" + SUBDIR + "/" + files.get(0).getFileName();
    }

    public String replace(Long userId, MultipartFile file) {
        if (file == null || file.isEmpty()) throw new IllegalArgumentException("No picture was provided.");
        if (file.getSize() > MAX_SIZE) throw new IllegalArgumentException("The picture is larger than 2 MB.");
        String type = file.getContentType() == null ? "" : file.getContentType().toLowerCase();
        if (!ALLOWED.contains(type)) throw new IllegalArgumentException("Only JPEG, PNG or WEBP pictures are allowed.");

        String ext = switch (type) {
            case "image/png" -> ".png";
            case "image/webp" -> ".webp";
            default -> ".jpg";
        };
        Path target = dir().resolve(userId + "-" + UUID.randomUUID() + ext);
        try {
            Files.createDirectories(target.getParent());
            file.transferTo(target);
        } catch (IOException e) {
            throw new UncheckedIOException("Failed to save the picture.", e);
        }
        filesOf(userId).stream().filter(p -> !p.equals(target)).forEach(this::deleteQuietly);
        return urlFor(userId);
    }

    public void remove(Long userId) {
        filesOf(userId).forEach(this::deleteQuietly);
    }

    private List<Path> filesOf(Long userId) {
        Path dir = dir();
        if (!Files.isDirectory(dir)) return List.of();
        String prefix = userId + "-";
        try (Stream<Path> s = Files.list(dir)) {
            return s.filter(p -> p.getFileName().toString().startsWith(prefix))
                .sorted((a, b) -> Long.compare(lastModified(b), lastModified(a)))  // newest first
                .toList();
        } catch (IOException e) {
            return List.of();
        }
    }

    private Path dir() {
        return Path.of(uploadDir).toAbsolutePath().normalize().resolve(SUBDIR);
    }

    private long lastModified(Path p) {
        try { return Files.getLastModifiedTime(p).toMillis(); } catch (IOException e) { return 0; }
    }

    private void deleteQuietly(Path p) {
        try { Files.deleteIfExists(p); } catch (IOException ignored) { }
    }
}
