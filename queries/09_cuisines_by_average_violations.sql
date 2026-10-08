/* ============================================================================
   Query 9 - Cuisines with the highest average violations per restaurant

   Business question:
     Which cuisine types average the most violations per restaurant, so that
     inspection effort or food-safety training could be targeted there?

   Reading the result: this counts violations cited during 2025, and a restaurant
   that fails an inspection is re-inspected sooner, so a high average partly
   reflects more inspections. It describes the inspection records, not the food.

   SQL concepts:
     - Querying a view, GROUP BY with AVG
     - HAVING as a minimum sample size: a cuisine with 3 restaurants can top any
       "average" list by chance, so only cuisines with at least 50 restaurants count
     - TOP (n) with ORDER BY on an aggregate
   ============================================================================ */
USE FlightsRestaurantsDB;
GO

SELECT TOP (10)
    v.CuisineName,
    COUNT(*)                                                 AS Restaurants,
    CAST(AVG(v.TotalViolations    * 1.0) AS decimal(5,2))    AS AvgViolationsPerRestaurant,
    CAST(AVG(v.CriticalViolations * 1.0) AS decimal(5,2))    AS AvgCriticalPerRestaurant,
    MAX(v.TotalViolations)                                   AS MostViolationsAtOneRestaurant
FROM dbo.vw_RestaurantViolationCounts AS v
WHERE v.CuisineName IS NOT NULL
GROUP BY v.CuisineName
HAVING COUNT(*) >= 50
ORDER BY AvgViolationsPerRestaurant DESC, v.CuisineName;
GO
