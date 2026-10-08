/* ============================================================================
   Query 7 - Airports with more departures than their country's average

   Business question:
     Which airports have more departing routes than the average airport in the
     same country? (the hubs of each country, measured against local traffic
     instead of one global threshold)

   "Average" = the average number of departing routes over the airports of that
   country that have at least one departure. Airports with no routes at all are
   left out, otherwise the thousands of unserved airfields would pull every
   country's average towards zero.

   SQL concepts:
     - Correlated subquery: the inner query references the outer row
       (peers.CountryId = d.CountryId), so it is logically evaluated once per airport
     - CTE reused by the outer query and by the subqueries
     - Integer division: AVG of an int is an int in SQL Server, hence the * 1.0

   Alternative: the same result can be written with a window function,
       AVG(Departures * 1.0) OVER (PARTITION BY CountryId),
   which scans the data once. The correlated form is kept on purpose - it is the
   concept this query demonstrates, and it reads closest to the question.
   ============================================================================ */
USE FlightsRestaurantsDB;
GO

WITH AirportDepartures AS
(
    SELECT
        a.AirportId,
        a.AirportName,
        a.IataCode,
        a.CountryId,
        COUNT(*) AS Departures
    FROM dbo.Airports AS a
    JOIN dbo.Routes AS r
        ON r.SourceAirportId = a.AirportId
    GROUP BY a.AirportId, a.AirportName, a.IataCode, a.CountryId
)
SELECT
    c.CountryName,
    d.IataCode,
    d.AirportName,
    d.Departures,
    -- Same correlated subquery again, only to display the value being compared.
    (
        SELECT CAST(AVG(peers.Departures * 1.0) AS decimal(10,1))
        FROM AirportDepartures AS peers
        WHERE peers.CountryId = d.CountryId
    ) AS CountryAvgDepartures
FROM AirportDepartures AS d
JOIN dbo.Countries AS c
    ON c.CountryId = d.CountryId
WHERE d.Departures > (
    SELECT AVG(peers.Departures * 1.0)
    FROM AirportDepartures AS peers
    WHERE peers.CountryId = d.CountryId      -- the correlation: "same country as the outer row"
)
ORDER BY c.CountryName, d.Departures DESC, d.AirportName;
GO
