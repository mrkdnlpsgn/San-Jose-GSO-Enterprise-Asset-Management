package com.sanjose.inventory.service;

import com.sanjose.inventory.dto.Article;
import com.sanjose.inventory.dto.ArticleRequest;
import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.exception.ResourceInUseException;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import jakarta.annotation.PostConstruct;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

// Articles: the managed list of item kinds under each category (ICT Equipment > Laptop),
// kept on the Categories page and picked on the asset form.
@Service
@RequiredArgsConstructor
@Transactional
public class ArticleService {

    private final JdbcTemplate jdbcTemplate;
    private final AuditLogService auditLogService;

    private static final RowMapper<Article> MAPPER = (rs, rn) ->
        new Article(rs.getLong("article_id"), rs.getLong("category_id"), rs.getString("article_name"));

    private static final String SELECT = "SELECT article_id, category_id, article_name FROM articles";

    // Created here rather than in a migration script so a fresh or hosted database
    // (Render/Aiven, where Hibernate DDL is off) gets them on the next deploy.
    // Also widens the asset condition columns to take NEW and GOOD. Every step is a no-op once done.
    @PostConstruct
    void ensureSchema() {
        jdbcTemplate.execute("""
            CREATE TABLE IF NOT EXISTS articles (
              article_id   INT NOT NULL AUTO_INCREMENT,
              category_id  INT NOT NULL,
              article_name VARCHAR(100) NOT NULL,
              created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
              PRIMARY KEY (article_id),
              UNIQUE KEY uq_articles_category_name (category_id, article_name),
              CONSTRAINT fk_articles_category FOREIGN KEY (category_id)
                REFERENCES categories (category_id) ON DELETE CASCADE
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
            """);
        if (!columnExists("assets", "article_id")) {
            jdbcTemplate.execute("ALTER TABLE assets ADD COLUMN article_id INT NULL AFTER category_id, "
                + "ADD KEY idx_assets_article (article_id), "
                + "ADD CONSTRAINT fk_assets_article FOREIGN KEY (article_id) REFERENCES articles (article_id)");
        }
        for (String table : List.of("assets", "deleted_assets")) {
            List<String> types = jdbcTemplate.queryForList(
                "SELECT COLUMN_TYPE FROM information_schema.COLUMNS "
                    + "WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = 'condition' AND DATA_TYPE = 'enum'",
                String.class, table);
            if (!types.isEmpty() && !types.get(0).contains("'GOOD'")) {
                jdbcTemplate.execute("ALTER TABLE " + table + " MODIFY `condition` "
                    + "enum('NEW','GOOD','SERVICEABLE','REPAIRABLE','UNSERVICEABLE') COLLATE utf8mb4_general_ci NOT NULL");
            }
        }
        seedDefaults();
    }

    // The usual articles under each standard category: "Article|description pattern|...". Each
    // pattern (a LIKE, the article name when none) links the existing assets of that category
    // whose description matches it; the first matching article in the list wins.
    private static final Map<String, List<String>> DEFAULT_ARTICLES = Map.of(
        "Appliances", List.of("Air Conditioner|%air condition%", "Electric Fan", "Refrigerator", "Microwave Oven",
            "Water Dispenser|%dispenser%", "Electric Kettle", "Vacuum Cleaner", "Television"),
        "ICT Equipment", List.of("Desktop Computer|%desktop%", "Laptop", "Monitor", "Printer", "Scanner", "Projector",
            "Network Switch|%switch%", "Router", "UPS|ups %|% ups|%(ups)%|%uninterruptible%", "External Hard Drive", "Tablet"),
        "Office Furniture", List.of("Office Desk|%desk%", "Office Chair|%office chair%", "Visitor's Chair|%visitor%",
            "Filing Cabinet", "Steel Locker|%locker%", "Bookshelf", "Conference Table", "Partition Panel|%partition%"),
        "Office Equipment", List.of("Photocopier", "Binding Machine", "Laminating Machine", "Paper Shredder|%shredder%",
            "Typewriter", "Fax Machine", "Calculator", "Cash Counting Machine", "Bulletin Board"),
        "Motor Vehicle", List.of("Ambulance", "Van|%van%|%hiace%", "Pick-up Truck|%pick-up%|%pickup%|%hilux%",
            "Dump Truck", "Sedan|%sedan%", "Motorcycle", "Utility Vehicle|%innova%"),
        "Heavy Equipment", List.of("Backhoe Loader|%backhoe%", "Bulldozer", "Road Roller", "Concrete Mixer",
            "Generator Set|%generator%", "Water Tanker Truck|%tanker%", "Grass Cutter"),
        "Communication Equipment", List.of("Base Radio|%base radio%|%vhf base%", "Two-Way Radio", "Megaphone", "Telephone|%phone%|%pabx%",
            "CCTV Camera", "DVR/NVR|%dvr%|%nvr%"),
        "Medical Equipment", List.of("Blood Pressure Monitor", "Nebulizer", "Autoclave", "Weighing Scale", "Thermal Scanner",
            "Oxygen Tank", "Stretcher", "Wheelchair"),
        "Agricultural Equipment", List.of("Hand Tractor", "Tractor", "Rice Thresher|%thresher%", "Water Pump", "Sprayer",
            "Farm Tool Kit|%tool kit%", "Seedling Tray|%seedling%", "Brush Cutter"),
        "Disaster & Rescue Equipment", List.of("Rescue Boat|%boat%", "Life Vest", "Rescue Rope|%rope%",
            "Emergency Light Tower|%light tower%", "Fire Extinguisher", "Chainsaw", "Metal Detector")
    );

    // Runs once, while no category has articles yet, so articles an admin later removes stay removed.
    // A category added under another name gets none; its articles are added on the Categories page.
    private void seedDefaults() {
        Integer any = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM articles", Integer.class);
        if (any != null && any > 0) return;
        DEFAULT_ARTICLES.forEach((category, entries) -> {
            List<Long> ids = jdbcTemplate.query("SELECT category_id FROM categories WHERE LOWER(category_name) = LOWER(?)",
                (rs, rn) -> rs.getLong(1), category);
            if (ids.isEmpty()) return;
            Long categoryId = ids.get(0);
            for (String entry : entries) {
                String[] parts = entry.split("\\|");
                String name = parts[0];
                jdbcTemplate.update("INSERT IGNORE INTO articles (category_id, article_name) VALUES (?, ?)", categoryId, name);
                Long articleId = idByName(categoryId, name);
                List<String> patterns = parts.length > 1 ? List.of(parts).subList(1, parts.length) : List.of("%" + name + "%");
                for (String pattern : patterns) {
                    jdbcTemplate.update("UPDATE assets SET article_id = ? WHERE category_id = ? AND article_id IS NULL "
                        + "AND LOWER(description) LIKE ?", articleId, categoryId, pattern.toLowerCase());
                }
            }
        });
    }

    private boolean columnExists(String table, String column) {
        Integer n = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?",
            Integer.class, table, column);
        return n != null && n > 0;
    }

    public List<Article> findAll(Long categoryId) {
        return categoryId == null
            ? jdbcTemplate.query(SELECT + " ORDER BY article_name", MAPPER)
            : jdbcTemplate.query(SELECT + " WHERE category_id = ? ORDER BY article_name", MAPPER, categoryId);
    }

    public Article findById(Long id) {
        List<Article> list = jdbcTemplate.query(SELECT + " WHERE article_id = ?", MAPPER, id);
        if (list.isEmpty()) throw new ResourceNotFoundException("Article not found: " + id);
        return list.get(0);
    }

    public Article create(ArticleRequest req) {
        String name = checkedName(req);
        if (req.getCategoryId() == null) throw new IllegalArgumentException("Category is required.");
        Integer cat = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM categories WHERE category_id = ?", Integer.class, req.getCategoryId());
        if (cat == null || cat == 0) throw new ResourceNotFoundException("Category not found: " + req.getCategoryId());
        checkUnique(req.getCategoryId(), name, null);
        jdbcTemplate.update("INSERT INTO articles (category_id, article_name) VALUES (?, ?)", req.getCategoryId(), name);
        Long id = jdbcTemplate.queryForObject("SELECT LAST_INSERT_ID()", Long.class);
        auditLogService.log("ARTICLE_CREATED", "Categories", id, "article", name);
        return findById(id);
    }

    // Renames only; an article stays in its category.
    public Article update(Long id, ArticleRequest req) {
        Article before = findById(id);
        String name = checkedName(req);
        checkUnique(before.getCategoryId(), name, id);
        jdbcTemplate.update("UPDATE articles SET article_name = ? WHERE article_id = ?", name, id);
        auditLogService.log("ARTICLE_UPDATED", "Categories", id, "article", before.getArticleName() + " -> " + name);
        return findById(id);
    }

    public void delete(Long id) {
        Article article = findById(id);
        Integer used = jdbcTemplate.queryForObject("SELECT COUNT(*) FROM assets WHERE article_id = ?", Integer.class, id);
        if (used != null && used > 0) {
            throw new ResourceInUseException("Cannot delete \"" + article.getArticleName() + "\": " + used
                + " asset(s) use it. Change those assets' article first.");
        }
        jdbcTemplate.update("DELETE FROM articles WHERE article_id = ?", id);
        auditLogService.log("ARTICLE_DELETED", "Categories", id, "article", article.getArticleName());
    }

    private static String checkedName(ArticleRequest req) {
        String name = req.getArticleName() == null ? "" : req.getArticleName().trim().replaceAll("\\s+", " ");
        if (name.isEmpty()) throw new IllegalArgumentException("Article name is required.");
        if (name.length() > 100) throw new IllegalArgumentException("Article name must be at most 100 characters.");
        return name;
    }

    private void checkUnique(Long categoryId, String name, Long excludeId) {
        Integer n = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM articles WHERE category_id = ? AND LOWER(article_name) = LOWER(?) AND (? IS NULL OR article_id <> ?)",
            Integer.class, categoryId, name, excludeId, excludeId);
        if (n != null && n > 0) throw new IllegalArgumentException("\"" + name + "\" is already an article in this category.");
    }

    // --- used by AssetService ---

    // The article an asset may be given: null when none, else it must be in the asset's category.
    public Long checkForCategory(Long articleId, Long categoryId) {
        if (articleId == null) return null;
        Article a = findById(articleId);
        if (!a.getCategoryId().equals(categoryId)) {
            throw new IllegalArgumentException("Article \"" + a.getArticleName() + "\" belongs to a different category.");
        }
        return articleId;
    }

    public Long idByName(Long categoryId, String name) {
        List<Long> ids = jdbcTemplate.query(
            "SELECT article_id FROM articles WHERE category_id = ? AND LOWER(article_name) = LOWER(?)",
            (rs, rn) -> rs.getLong(1), categoryId, name.trim());
        return ids.isEmpty() ? null : ids.get(0);
    }

    public void setOnAsset(Long assetId, Long articleId) {
        jdbcTemplate.update("UPDATE assets SET article_id = ? WHERE asset_id = ?", articleId, assetId);
    }

    // Fills in each asset's article. One query for the lot, so a full list stays one round trip.
    public void attach(List<Asset> assets) {
        if (assets.isEmpty()) return;
        Map<Long, Article> byAsset = new HashMap<>();
        String sql = "SELECT a.asset_id, ar.article_id, ar.category_id, ar.article_name FROM assets a "
            + "JOIN articles ar ON ar.article_id = a.article_id";
        if (assets.size() == 1) {
            jdbcTemplate.query(sql + " WHERE a.asset_id = ?", rs -> {
                byAsset.put(rs.getLong(1), new Article(rs.getLong(2), rs.getLong(3), rs.getString(4)));
            }, assets.get(0).getId());
        } else {
            jdbcTemplate.query(sql, rs -> {
                byAsset.put(rs.getLong(1), new Article(rs.getLong(2), rs.getLong(3), rs.getString(4)));
            });
        }
        for (Asset a : assets) a.setArticle(byAsset.get(a.getId()));
    }
}
