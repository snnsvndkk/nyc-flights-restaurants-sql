/* ============================================================================
   Query 10 - How are restaurants distributed by number of critical violations?

   Business question:
     What share of inspected restaurants had no critical violation in 2025, and
     how many fall into each band (1-2, 3-5, 6-10, more than 10)? In other words:
     is the problem spread evenly or concentrated in a small group?

   SQL concepts:
     - Table value constructor: (VALUES ...) used as a small inline lookup table
     - Non-equi join: joining on a range (BETWEEN) instead of on equality
     - Window aggregates on top of GROUP BY: SUM(COUNT(*)) OVER () for
       percent-of-total, and OVER (ORDER BY ...) for a running total
   ============================================================================ */
USE FlightsRestaurantsDB;
GO

SELECT
    band.Label AS CriticalViolations,
    COUNT(*)   AS Restaurants,
    -- COUNT(*) is the size of one group. SUM(COUNT(*)) OVER () adds the sizes of all
    -- groups = the total number of restaurants, without running a second query.
    CAST(100.0 * COUNT(*) / SUM(COUNT(*)) OVER () AS decimal(5,1)) AS PctOfRestaurants,
    -- Running total: share of restaurants in this band or a lower one.
    CAST(100.0 * SUM(COUNT(*)) OVER (ORDER BY band.SortOrder)
               / SUM(COUNT(*)) OVER () AS decimal(5,1))            AS CumulativePct
FROM dbo.vw_RestaurantViolationCounts AS v
JOIN (VALUES
        (1, '0',            0,  0),
        (2, '1-2',          1,  2),
        (3, '3-5',          3,  5),
        (4, '6-10',         6,  10),
        (5, 'more than 10', 11, 2147483647)
     ) AS band (SortOrder, Label, MinViolations, MaxViolations)
    ON v.CriticalViolations BETWEEN band.MinViolations AND band.MaxViolations
GROUP BY band.SortOrder, band.Label
ORDER BY band.SortOrder;
GO
