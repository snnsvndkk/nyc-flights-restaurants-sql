/* ============================================================================
   Query 6 - Top 3 airlines by route count within each country

   Business question:
     In each country, which three airlines operate the most routes departing
     from that country's airports? (who dominates each national market)

   Interpretation: "within each country" = the country of the departure airport.
   It is not the airline's home country - a foreign low-cost carrier can be number
   one in a country, and that is exactly what this query is meant to show.

   SQL concepts:
     - Window function: RANK() OVER (PARTITION BY ... ORDER BY ...)
     - Ranking an aggregate: the window function runs after GROUP BY, so it can
       order by COUNT(*)
     - A CTE is needed to filter on the rank: window functions are evaluated after
       WHERE, so "WHERE RANK() ... <= 3" is not allowed in the same SELECT
   ============================================================================ */
USE FlightsRestaurantsDB;
GO

/* RANK vs ROW_NUMBER vs DENSE_RANK for counts 10, 8, 8, 5:
     ROW_NUMBER  1, 2, 3, 4   always exactly 3 rows, but a tie is cut arbitrarily
     RANK        1, 2, 2, 4   tied airlines share a rank, so nobody is dropped unfairly
     DENSE_RANK  1, 2, 2, 3   like RANK but without gaps -> would return 4 rows here
   RANK is used: a country can return more than 3 rows only when there is a real tie
   for third place. */
WITH AirlineRoutesByCountry AS
(
    SELECT
        c.CountryId,
        c.CountryName,
        al.AirlineId,
        al.AirlineName,
        COUNT(*) AS RouteCount,
        RANK() OVER (
            PARTITION BY c.CountryId        -- restart the ranking for every country
            ORDER BY COUNT(*) DESC          -- most routes first
        ) AS RankInCountry
    FROM dbo.Routes AS r
    JOIN dbo.Airports AS src
        ON src.AirportId = r.SourceAirportId
    JOIN dbo.Countries AS c
        ON c.CountryId = src.CountryId
    JOIN dbo.Airlines AS al
        ON al.AirlineId = r.AirlineId
    GROUP BY c.CountryId, c.CountryName, al.AirlineId, al.AirlineName
)
SELECT
    CountryName,
    RankInCountry,
    AirlineName,
    RouteCount
FROM AirlineRoutesByCountry
WHERE RankInCountry <= 3
ORDER BY CountryName, RankInCountry, AirlineName;
GO
