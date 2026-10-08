/* ============================================================================
   Query 2 - All routes arriving at JFK

   Business question:
     Which routes arrive at New York JFK? For each one show the origin airport,
     its city and country, and the airline that flies it.

   SQL concepts:
     - Multi-table INNER JOINs (5 joins)
     - Joining the same table twice with different aliases (Airports as the
       destination and as the origin - a role-playing table)
     - Filtering on a joined table, ORDER BY on several columns
   ============================================================================ */
USE FlightsRestaurantsDB;
GO

SELECT
    al.AirlineName,
    origin.IataCode     AS OriginCode,
    origin.AirportName  AS OriginAirport,
    origin.City         AS OriginCity,
    oc.CountryName      AS OriginCountry,
    r.Stops,
    r.IsCodeshare
FROM dbo.Routes AS r
JOIN dbo.Airports AS dest                  -- the airport the route arrives at
    ON dest.AirportId = r.DestAirportId
JOIN dbo.Airports AS origin                -- the airport the route departs from
    ON origin.AirportId = r.SourceAirportId
JOIN dbo.Countries AS oc
    ON oc.CountryId = origin.CountryId
JOIN dbo.Airlines AS al
    ON al.AirlineId = r.AirlineId
WHERE dest.IataCode = 'JFK'
ORDER BY oc.CountryName, origin.City, al.AirlineName;
GO
