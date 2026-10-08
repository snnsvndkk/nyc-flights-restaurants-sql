/* ============================================================================
   Query 3 - Number of airports per country

   Business questions:
     A) Which 15 countries have the most airports?
     B) Which countries have more than 100 airports?

   SQL concepts:
     - GROUP BY with COUNT(*)
     - HAVING (filters groups, after aggregation) versus WHERE (filters rows, before)
     - ORDER BY an aggregate, TOP (n)
   ============================================================================ */
USE FlightsRestaurantsDB;
GO

/* A) Top 15 countries by airport count.
   TOP without ORDER BY would return 15 arbitrary rows, so the ORDER BY is what makes
   it a "top" list. The country name is a tie-breaker that keeps the result
   deterministic. Grouping is by CountryId because it is the key; the name is added
   so it can be selected. */
SELECT TOP (15)
    c.CountryName,
    COUNT(*) AS AirportCount
FROM dbo.Airports AS a
JOIN dbo.Countries AS c
    ON c.CountryId = a.CountryId
GROUP BY c.CountryId, c.CountryName
ORDER BY AirportCount DESC, c.CountryName;
GO

/* B) Countries with more than 100 airports.
   The condition is on COUNT(*), which only exists after grouping, so it must go in
   HAVING - a WHERE clause cannot reference an aggregate. */
SELECT
    c.CountryName,
    COUNT(*) AS AirportCount
FROM dbo.Airports AS a
JOIN dbo.Countries AS c
    ON c.CountryId = a.CountryId
GROUP BY c.CountryId, c.CountryName
HAVING COUNT(*) > 100
ORDER BY AirportCount DESC, c.CountryName;
GO
