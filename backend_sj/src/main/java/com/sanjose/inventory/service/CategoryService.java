package com.sanjose.inventory.service;

import com.sanjose.inventory.config.SpHelper;
import com.sanjose.inventory.dto.CategoryRequest;
import com.sanjose.inventory.entity.Category;
import com.sanjose.inventory.exception.ResourceInUseException;
import com.sanjose.inventory.exception.ResourceNotFoundException;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
@Transactional
public class CategoryService {

    private final JdbcTemplate jdbcTemplate;
    private final AuditLogService auditLogService;

    private static final RowMapper<Category> CAT_MAPPER = (rs, rn) -> {
        Category c = new Category();
        c.setId(rs.getLong("id"));
        c.setCategoryName(rs.getString("categoryName"));
        c.setDescription(rs.getString("description"));
        return c;
    };

    public List<Category> findAll(String search) {
        if (search != null && !search.isBlank()) {
            return jdbcTemplate.query("CALL sp_categories_search(?)", CAT_MAPPER, search.trim());
        }
        return jdbcTemplate.query("CALL sp_categories_get_all()", CAT_MAPPER);
    }

    public Category findById(Long id) {
        List<Category> list = jdbcTemplate.query("CALL sp_categories_get_by_id(?)", CAT_MAPPER, id);
        if (list.isEmpty()) throw new ResourceNotFoundException("Category not found: " + id);
        return list.get(0);
    }

    public Category create(CategoryRequest req) {
        Boolean exists = SpHelper.callWithOutBoolean(jdbcTemplate,
            "CALL sp_categories_name_exists(?, ?)", req.getCategoryName());
        if (Boolean.TRUE.equals(exists)) {
            throw new IllegalArgumentException("Category name already exists: " + req.getCategoryName());
        }
        Long newId = SpHelper.callWithOutLong(jdbcTemplate,
            "CALL sp_categories_create(?, ?, ?)",
            req.getCategoryName(), req.getDescription());
        Category saved = findById(newId);
        auditLogService.log("CATEGORY_CREATED", "Categories", newId, "category", saved.getCategoryName());
        return saved;
    }

    public Category update(Long id, CategoryRequest req) {
        findById(id); // throws if not found
        jdbcTemplate.update("CALL sp_categories_update(?, ?, ?)",
            id, req.getCategoryName(), req.getDescription());
        Category saved = findById(id);
        auditLogService.log("CATEGORY_UPDATED", "Categories", id, "category", saved.getCategoryName());
        return saved;
    }

    public void delete(Long id) {
        Category cat = findById(id);
        // assets.category_id is a NO ACTION FK — deleting while assets are still
        // assigned to this category would otherwise fail as a raw SQL constraint
        // error. Check first so the caller gets an actionable message instead.
        Integer assetCount = jdbcTemplate.queryForObject(
            "SELECT COUNT(*) FROM assets WHERE category_id = ?", Integer.class, id);
        if (assetCount != null && assetCount > 0) {
            throw new ResourceInUseException(
                "Cannot delete \"" + cat.getCategoryName() + "\" — " + assetCount +
                " asset(s) are still assigned to it. Reassign or remove those assets first.");
        }
        jdbcTemplate.update("CALL sp_categories_delete(?)", id);
        auditLogService.log("CATEGORY_DELETED", "Categories", id, "category", cat.getCategoryName());
    }
}
