package com.sanjose.inventory.service;

import org.junit.jupiter.api.Test;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.Random;

import static org.junit.jupiter.api.Assertions.*;

class RepairRiskModelTest {

    // kindRate drives the label; the other features are noise
    private static void rows(int n, long seed, List<double[]> xs, List<Boolean> ys) {
        Random r = new Random(seed);
        for (int i = 0; i < n; i++) {
            double kindRate = r.nextDouble();
            xs.add(new double[]{r.nextDouble() * 15, r.nextInt(2), r.nextInt(3), r.nextDouble() * 3, kindRate, r.nextDouble() * 8});
            ys.add(r.nextDouble() < kindRate * 0.8);
        }
    }

    @Test
    void learnsWhichFactorMattersAndRanksWellOnUnseenRows() {
        List<double[]> xs = new ArrayList<>();
        List<Boolean> ys = new ArrayList<>();
        rows(3000, 1, xs, ys);
        RepairRiskService.Model model = RepairRiskService.fit(xs, ys);
        int kind = List.of(RepairRiskService.FEATURES).indexOf("kindRate");
        for (int j = 0; j < model.w().length; j++) {
            if (j != kind) assertTrue(Math.abs(model.w()[j]) < Math.abs(model.w()[kind]) / 4, "feature " + j + " should matter little");
        }
        assertTrue(model.chance(new double[]{5, 0, 0, 1, 0.9, 4}) > model.chance(new double[]{5, 0, 0, 1, 0.1, 4}));

        List<double[]> testX = new ArrayList<>();
        List<Boolean> testY = new ArrayList<>();
        rows(1000, 2, testX, testY);
        Map<String, Object> check = RepairRiskService.check(model, testX, testY, 2025);
        assertEquals(1000, check.get("assets"));
        assertTrue((Double) check.get("auc") > 0.7, "auc " + check.get("auc"));
        assertTrue((Double) check.get("foundPercent") > (Double) check.get("randomPercent"));
    }

    @Test
    void checkOfAPerfectRankingFindsEveryCase() {
        RepairRiskService.Model model = new RepairRiskService.Model(new double[6], new double[]{1, 1, 1, 1, 1, 1},
            new double[]{0, 0, 0, 0, 5, 0}, 0);
        List<double[]> xs = new ArrayList<>();
        List<Boolean> ys = new ArrayList<>();
        for (int i = 0; i < 10; i++) {
            xs.add(new double[]{0, 0, 0, 0, i / 10.0, 0});
            ys.add(i >= 7);
        }
        Map<String, Object> check = RepairRiskService.check(model, xs, ys, 2025);
        assertEquals(3, check.get("needed"));
        assertEquals(3, check.get("found"));
        assertEquals(100.0, check.get("foundPercent"));
        assertEquals(30.0, check.get("randomPercent"));
        assertEquals(1.0, check.get("auc"));
    }

    @Test
    void reasonsOnlyNameFactorsThatRaiseTheChance() {
        // newer assets score higher (negative age weight): age must not be given as a reason
        RepairRiskService.Model model = new RepairRiskService.Model(new double[]{8, 0, 0, 0, 0.2, 0}, new double[]{4, 1, 1, 1, 0.1, 1},
            new double[]{-1, 0, 0, 0, 1, 0}, 0);
        RepairRiskService.Asset asset = new RepairRiskService.Asset(1, "P-1", "Aircon", "Appliances", "Air Conditioner",
            "GSO", 0, Long.MAX_VALUE, 30000, new long[0], new double[0]);
        List<String> reasons = RepairRiskService.reasons(model, new double[]{1, 0, 0, 0, 0.5, 0}, asset);
        assertEquals(List.of("50% of Air Conditioner needed work last year"), reasons);
    }
}
