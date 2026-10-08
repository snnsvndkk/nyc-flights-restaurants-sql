/* ============================================================================
   Query 4 - The 20 longest routes by great-circle distance

   Business question:
     What are the 20 longest routes (origin -> destination), how long are they in
     kilometres, and which airlines sell them?

   SQL concepts:
     - Reusing a view: the haversine distance is computed once, in
       dbo.vw_RouteDistances (see views/vw_RouteDistances.sql for the formula)
     - GROUP BY to collapse the same airport pair flown by several airlines
     - STRING_AGG ... WITHIN GROUP (ORDER BY ...) to list those airlines in one cell
     - TOP (n) with ORDER BY

   Data-quality note:
     OpenFlights contains a few airport records whose coordinates belong to a
     different airport. Example: airport id 5613 is listed as Solwesi, Zambia, but
     carries the name and coordinates of Los Alamitos Army Air Field in California,
     which turns a short domestic Zambian flight into a 16,082 km "route".
     The bad records found while checking this result all lack an IATA code, and
     airports with scheduled airline service normally have one, so this query only
     ranks routes where both airports have an IATA code. The view itself still
     contains every route.
   ============================================================================ */
USE FlightsRestaurantsDB;
GO

SELECT TOP (20)
    d.SourceCode,
    d.SourceCity,
    d.SourceCountry,
    d.DestCode,
    d.DestCity,
    d.DestCountry,
    d.DistanceKm,
    COUNT(*)                                                     AS AirlineCount,
    STRING_AGG(d.AirlineName, ', ') WITHIN GROUP (ORDER BY d.AirlineName) AS Airlines
FROM dbo.vw_RouteDistances AS d
WHERE d.SourceCode IS NOT NULL
  AND d.DestCode   IS NOT NULL
GROUP BY
    d.SourceAirportId, d.SourceCode, d.SourceCity, d.SourceCountry,
    d.DestAirportId,   d.DestCode,   d.DestCity,   d.DestCountry,
    d.DistanceKm
ORDER BY d.DistanceKm DESC, d.SourceCode, d.DestCode;
GO
