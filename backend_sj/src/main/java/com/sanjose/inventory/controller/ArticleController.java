package com.sanjose.inventory.controller;

import com.sanjose.inventory.dto.Article;
import com.sanjose.inventory.dto.ArticleRequest;
import com.sanjose.inventory.service.ArticleService;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/articles")
@RequiredArgsConstructor
public class ArticleController {

    private final ArticleService articleService;

    @GetMapping
    public List<Article> getAll(@RequestParam(required = false) Long categoryId) { return articleService.findAll(categoryId); }

    @PostMapping
    public Article create(@RequestBody ArticleRequest req) { return articleService.create(req); }

    @PutMapping("/{id}")
    public Article update(@PathVariable Long id, @RequestBody ArticleRequest req) { return articleService.update(id, req); }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id) {
        articleService.delete(id);
        return ResponseEntity.noContent().build();
    }
}
