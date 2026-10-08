/* ============================================================================
   Query 1 - Airports with no departing routes

   Business question:
     Which airports are in our airport list but have no scheduled route departing
     from them? (military fields, private strips, closed or unserved airports -
     the ones a route planner should not offer as an origin)

   SQL concepts:
     - Anti-join, written two equivalent ways:
         A) NOT EXISTS with a correlated subquery
         B) LEFT JOIN ... WHERE <right side> IS NULL
     - INNER JOIN to a lookup table (Countries)

   Both statements return exactly the same rows.
   ============================================================================ */
USE FlightsRestaurantsDB;
GO

/* A) NOT EXISTS
   For each airport the subquery asks "is there at least one route that departs from
   here?". NOT EXISTS keeps the airport only when the answer is no.
   SELECT 1 is a convention: EXISTS only checks whether a row exists and ignores
   the select list. */
SELECT
    a.AirportId,
    a.AirportName,
    a.City,
    c.CountryName,
    a.IataCode
FROM dbo.Airports AS a
JOIN dbo.Countries AS c
    ON c.CountryId = a.CountryId
WHERE NOT EXISTS (
    SELECT 1
    FROM dbo.Routes AS r
    WHERE r.SourceAirportId = a.AirportId
)
ORDER BY c.CountryName, a.AirportName;
GO

/* B) LEFT JOIN ... IS NULL
   The LEFT JOIN keeps every airport. Airports without a matching route get NULLs in
   all Routes columns, and the WHERE clause keeps only those.
   The test is on r.RouteId because it is the primary key and can never be NULL in a
   real row - so NULL can only mean "no match".

   Why prefer NOT EXISTS: it states the intent directly, and it stays correct in cases
   where NOT IN breaks (NOT IN returns no rows if the subquery yields a NULL). */
SELECT
    a.AirportId,
    a.AirportName,
    a.City,
    c.CountryName,
    a.IataCode
FROM dbo.Airports AS a
JOIN dbo.Countries AS c
    ON c.CountryId = a.CountryId
LEFT JOIN dbo.Routes AS r
    ON r.SourceAirportId = a.AirportId
WHERE r.RouteId IS NULL
ORDER BY c.CountryName, a.AirportName;
GO
