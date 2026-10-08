/* ============================================================================
   Query 8 - Boroughs with the most critical violations

   Business question:
     Which NYC boroughs had the most critical food-safety violations in 2025,
     and is that only because they have more restaurants? (total, share of all
     violations that are critical, and average per restaurant)

   SQL concepts:
     - Querying a view (dbo.vw_RestaurantViolationCounts) like a table
     - GROUP BY with several aggregates: COUNT, SUM, AVG
     - Ratios: decimal arithmetic to avoid integer division, NULLIF to avoid
       division by zero
   ============================================================================ */
USE FlightsRestaurantsDB;
GO

SELECT
    v.BoroughName,
    COUNT(*)                   AS Restaurants,
    SUM(v.TotalViolations)     AS TotalViolations,
    SUM(v.CriticalViolations)  AS CriticalViolations,
    -- 100.0 makes the division decimal; NULLIF turns a zero divisor into NULL
    -- (the result is then NULL instead of a divide-by-zero error).
    CAST(100.0 * SUM(v.CriticalViolations) / NULLIF(SUM(v.TotalViolations), 0) AS decimal(5,1)) AS CriticalPct,
    CAST(AVG(v.CriticalViolations * 1.0) AS decimal(5,2))                                       AS AvgCriticalPerRestaurant
FROM dbo.vw_RestaurantViolationCounts AS v
WHERE v.BoroughName IS NOT NULL        -- 20 restaurants have no borough in the source
GROUP BY v.BoroughName
ORDER BY CriticalViolations DESC;
GO
