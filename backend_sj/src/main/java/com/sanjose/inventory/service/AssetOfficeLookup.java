package com.sanjose.inventory.service;

import com.sanjose.inventory.entity.Asset;
import com.sanjose.inventory.entity.Office;
import lombok.RequiredArgsConstructor;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;

import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

// The maintenance and disposal procedures return only a few columns of each record's asset, and
// not its office. It is looked up here, one query per list, so a record's view can show it.
@Service
@RequiredArgsConstructor
public class AssetOfficeLookup {

    private final JdbcTemplate jdbcTemplate;

    public void attach(List<Asset> assets) {
        List<Long> ids = assets.stream().filter(Objects::nonNull).map(Asset::getId).filter(Objects::nonNull).distinct().toList();
        if (ids.isEmpty()) return;
        Map<Long, Office> offices = new HashMap<>();
        String marks = String.join(", ", Collections.nCopies(ids.size(), "?"));
        jdbcTemplate.query("SELECT a.asset_id, o.office_id, o.office_name FROM assets a JOIN offices o ON o.office_id = a.office_id "
                + "WHERE a.asset_id IN (" + marks + ")",
            rs -> {
                Office o = new Office();
                o.setId(rs.getLong(2));
                o.setOfficeName(rs.getString(3));
                offices.put(rs.getLong(1), o);
            }, ids.toArray());
        assets.stream().filter(Objects::nonNull).forEach(a -> a.setOffice(offices.get(a.getId())));
    }
}
