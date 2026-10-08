/* ============================================================================
   View: dbo.vw_RouteDistances

   Purpose:
     Every route with readable airline / airport names and its great-circle
     distance in kilometres, so no query has to repeat the distance formula.
     Used by queries/04_longest_routes.sql.

   Haversine formula (distance between two points on a sphere):
       a = sin^2((lat2 - lat1) / 2) + cos(lat1) * cos(lat2) * sin^2((lon2 - lon1) / 2)
       d = 2 * R * asin(sqrt(a))          R = 6371 km, the mean radius of the Earth
     All angles are in radians.

   SQL concepts:
     - CREATE OR ALTER VIEW (re-runnable)
     - CROSS APPLY to name an intermediate expression once and reuse it
     - Math functions: RADIANS, SIN, COS, ASIN, SQRT, POWER
   ============================================================================ */
USE FlightsRestaurantsDB;
GO

CREATE OR ALTER VIEW dbo.vw_RouteDistances
AS
SELECT
    r.RouteId,
    r.AirlineId,
    al.AirlineName,
    r.SourceAirportId,
    src.IataCode     AS SourceCode,
    src.AirportName  AS SourceAirport,
    src.City         AS SourceCity,
    sc.CountryName   AS SourceCountry,
    r.DestAirportId,
    dst.IataCode     AS DestCode,
    dst.AirportName  AS DestAirport,
    dst.City         AS DestCity,
    dc.CountryName   AS DestCountry,
    r.Stops,
    r.IsCodeshare,
    CAST(ROUND(2 * 6371.0 * ASIN(SQRT(h.A)), 1) AS decimal(7,1)) AS DistanceKm
FROM dbo.Routes AS r
JOIN dbo.Airlines  AS al  ON al.AirlineId  = r.AirlineId
JOIN dbo.Airports  AS src ON src.AirportId = r.SourceAirportId
JOIN dbo.Airports  AS dst ON dst.AirportId = r.DestAirportId
JOIN dbo.Countries AS sc  ON sc.CountryId  = src.CountryId
JOIN dbo.Countries AS dc  ON dc.CountryId  = dst.CountryId
-- Step 1: degrees -> radians. Cast to float first: RADIANS() of a decimal(9,6)
-- returns a decimal with only 6 decimals, which would lose precision.
CROSS APPLY (
    SELECT
        RADIANS(CAST(src.Latitude  AS float)) AS Lat1,
        RADIANS(CAST(src.Longitude AS float)) AS Lon1,
        RADIANS(CAST(dst.Latitude  AS float)) AS Lat2,
        RADIANS(CAST(dst.Longitude AS float)) AS Lon2
) AS rad
-- Step 2: the "a" term of the haversine formula. Rounding errors can push it a hair
-- above 1 for points on opposite sides of the globe, and ASIN(>1) is an error, so it
-- is capped at 1.
CROSS APPLY (
    SELECT
        CASE WHEN x.A > 1 THEN 1 ELSE x.A END AS A
    FROM (
        SELECT
            POWER(SIN((rad.Lat2 - rad.Lat1) / 2), 2)
            + COS(rad.Lat1) * COS(rad.Lat2) * POWER(SIN((rad.Lon2 - rad.Lon1) / 2), 2) AS A
    ) AS x
) AS h;
GO
