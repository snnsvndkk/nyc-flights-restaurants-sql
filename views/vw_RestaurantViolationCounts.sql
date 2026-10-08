/* ============================================================================
   View: dbo.vw_RestaurantViolationCounts

   Purpose:
     One row per restaurant with its name, borough, cuisine, number of
     inspections, total violations and critical violations. The base for the
     restaurant analysis queries (queries/08 - 10).

   SQL concepts:
     - CREATE OR ALTER VIEW
     - LEFT JOINs so restaurants with no violations are kept (with a count of 0)
     - Conditional aggregation: SUM(CASE WHEN ... THEN 1 ELSE 0 END)
     - COUNT(column) vs COUNT(*) vs COUNT(DISTINCT ...)
   ============================================================================ */
USE FlightsRestaurantsDB;
GO

CREATE OR ALTER VIEW dbo.vw_RestaurantViolationCounts
AS
SELECT
    r.RestaurantId,
    r.RestaurantName,
    b.BoroughName,
    c.CuisineName,
    -- An inspection with 3 violations appears on 3 joined rows, so count it once.
    COUNT(DISTINCT i.InspectionId)                        AS InspectionCount,
    -- COUNT(column) skips NULLs: a restaurant whose LEFT JOIN found no violation
    -- gets 0 here, where COUNT(*) would wrongly give 1.
    COUNT(iv.ViolationCode)                               AS TotalViolations,
    SUM(CASE WHEN iv.IsCritical = 1 THEN 1 ELSE 0 END)    AS CriticalViolations
FROM dbo.Restaurants AS r
LEFT JOIN dbo.Boroughs AS b
    ON b.BoroughId = r.BoroughId
LEFT JOIN dbo.Cuisines AS c
    ON c.CuisineId = r.CuisineId
LEFT JOIN dbo.Inspections AS i
    ON i.RestaurantId = r.RestaurantId
LEFT JOIN dbo.InspectionViolations AS iv
    ON iv.InspectionId = i.InspectionId
GROUP BY
    r.RestaurantId,
    r.RestaurantName,
    b.BoroughName,
    c.CuisineName;
GO
