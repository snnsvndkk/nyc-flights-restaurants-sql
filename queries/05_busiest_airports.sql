/* ============================================================================
   Query 5 - Busiest airports by number of routes

   Business question:
     Which 20 airports are the biggest hubs, counting the routes that depart
     from them and the routes that arrive at them?

   SQL concepts:
     - Common table expressions (two CTEs in one WITH)
     - Aggregating BEFORE joining, to avoid row multiplication (fan-out)
     - LEFT JOIN + ISNULL for airports that only have departures or only arrivals
   ============================================================================ */
USE FlightsRestaurantsDB;
GO

/* Why two CTEs instead of joining Routes to Airports twice?
   An airport with 900 departures and 900 arrivals would produce 900 x 900 joined rows
   and both counts would be wrong. Each CTE first reduces Routes to one row per
   airport, so the final joins are one-to-one. */
WITH Departures AS
(
    SELECT r.SourceAirportId AS AirportId, COUNT(*) AS DepartingRoutes
    FROM dbo.Routes AS r
    GROUP BY r.SourceAirportId
),
Arrivals AS
(
    SELECT r.DestAirportId AS AirportId, COUNT(*) AS ArrivingRoutes
    FROM dbo.Routes AS r
    GROUP BY r.DestAirportId
)
SELECT TOP (20)
    a.IataCode,
    a.AirportName,
    a.City,
    c.CountryName,
    ISNULL(dep.DepartingRoutes, 0)                                AS DepartingRoutes,
    ISNULL(arr.ArrivingRoutes, 0)                                 AS ArrivingRoutes,
    ISNULL(dep.DepartingRoutes, 0) + ISNULL(arr.ArrivingRoutes, 0) AS TotalRoutes
FROM dbo.Airports AS a
JOIN dbo.Countries AS c
    ON c.CountryId = a.CountryId
LEFT JOIN Departures AS dep
    ON dep.AirportId = a.AirportId
LEFT JOIN Arrivals AS arr
    ON arr.AirportId = a.AirportId
WHERE dep.AirportId IS NOT NULL
   OR arr.AirportId IS NOT NULL
ORDER BY TotalRoutes DESC, a.AirportName;
GO
