/* Staging -> clean tables for the OpenFlights data.

   Cleaning rules (each one comes from profiling the raw files):
     - OpenFlights writes NULL as the two characters \N         -> NULLIF(col, '\N')
     - empty strings also mean "unknown"                         -> NULLIF(col, '')
     - apostrophes are escaped as \' or \\' (Port O\'Connor)     -> REPLACE
     - numbers arrive as text                                    -> TRY_CONVERT (NULL instead of an error)
     - IATA / ICAO codes must have the right length and only letters or digits, otherwise
       NULL (the airline file contains junk codes such as '-', 'N/A', '??', '+-')
     - a route is kept only if its airline and both airports exist, because the
       foreign keys require it; the rejected rows are counted at the end

   Load order follows the foreign keys: Countries -> Airports -> Airlines -> Routes.
   Everything runs in one transaction, so a failure leaves the tables empty, never half-loaded. */
USE FlightsRestaurantsDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;          -- any run-time error rolls back the whole transaction
SET QUOTED_IDENTIFIER ON;   -- required to insert into a table that has filtered indexes

BEGIN TRANSACTION;

/* ---------- Countries ----------
   The country list is the set of country names used by airports. Airline
   countries are matched against this list further down. */
INSERT INTO dbo.Countries (CountryName)
SELECT DISTINCT LTRIM(RTRIM(s.Country))
FROM stg.Airports AS s
WHERE NULLIF(NULLIF(LTRIM(RTRIM(s.Country)), '\N'), '') IS NOT NULL
ORDER BY 1;

/* ---------- Airports ---------- */
INSERT INTO dbo.Airports
    (AirportId, AirportName, City, CountryId, IataCode, IcaoCode,
     Latitude, Longitude, AltitudeFt, UtcOffset, DstCode, TimeZoneName)
SELECT
    TRY_CONVERT(int, s.AirportId),
    REPLACE(REPLACE(LTRIM(RTRIM(s.Name)), '\\''', ''''), '\''', ''''),
    REPLACE(REPLACE(NULLIF(NULLIF(LTRIM(RTRIM(s.City)), '\N'), ''), '\\''', ''''), '\''', ''''),
    c.CountryId,
    CASE WHEN s.Iata LIKE '[A-Z0-9][A-Z0-9][A-Z0-9]'        THEN UPPER(s.Iata) END,
    CASE WHEN s.Icao LIKE '[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]' THEN UPPER(s.Icao) END,
    -- The file has up to 15 decimals; go through float, then round to 6 decimals.
    CONVERT(decimal(9,6), TRY_CONVERT(float, s.Latitude)),
    CONVERT(decimal(9,6), TRY_CONVERT(float, s.Longitude)),
    TRY_CONVERT(int, s.AltitudeFt),
    TRY_CONVERT(decimal(4,2), NULLIF(s.UtcOffset, '\N')),
    NULLIF(NULLIF(s.Dst, '\N'), ''),
    NULLIF(NULLIF(s.TzDatabase, '\N'), '')
FROM stg.Airports AS s
JOIN dbo.Countries AS c
    ON c.CountryName = LTRIM(RTRIM(s.Country))
WHERE TRY_CONVERT(int, s.AirportId) IS NOT NULL
  AND TRY_CONVERT(float, s.Latitude)  IS NOT NULL
  AND TRY_CONVERT(float, s.Longitude) IS NOT NULL;

/* ---------- Airlines ----------
   The airline file spells some countries differently from the airport file.
   CountryAliases maps those spellings to the name used in dbo.Countries. Values that are
   not a country at all (the file sometimes has a callsign in this column, e.g. 'ALASKA')
   stay unmatched and get CountryId = NULL - the load does not guess. */
WITH CountryAliases (SourceName, CountryName) AS
(
    SELECT v.SourceName, v.CountryName
    FROM (VALUES
        (N'Republic of Korea',                     N'South Korea'),
        (N'Democratic People''s Republic of Korea', N'North Korea'),
        (N'Hong Kong SAR of China',                N'Hong Kong'),
        (N'Macao',                                 N'Macau'),
        (N'Lao Peoples Democratic Republic',       N'Laos'),
        (N'Russian Federation',                    N'Russia'),
        (N'Syrian Arab Republic',                  N'Syria'),
        (N'Somali Republic',                       N'Somalia'),
        (N'Ivory Coast',                           N'Cote d''Ivoire'),
        (N'Republic of the Congo',                 N'Congo (Brazzaville)'),
        (N'Democratic Republic of the Congo',      N'Congo (Kinshasa)'),
        (N'Democratic Republic of Congo',          N'Congo (Kinshasa)'),
        (N'Netherland',                            N'Netherlands')
    ) AS v (SourceName, CountryName)
),
CleanAirlines AS
(
    SELECT
        TRY_CONVERT(int, s.AirlineId) AS AirlineId,
        REPLACE(REPLACE(LTRIM(RTRIM(s.Name)), '\\''', ''''), '\''', '''')                              AS AirlineName,
        REPLACE(REPLACE(NULLIF(NULLIF(LTRIM(RTRIM(s.Alias)), '\N'), ''), '\\''', ''''), '\''', '''')    AS Alias,
        CASE WHEN s.Iata LIKE '[A-Z0-9][A-Z0-9]'        THEN UPPER(s.Iata) END                          AS IataCode,
        CASE WHEN s.Icao LIKE '[A-Z0-9][A-Z0-9][A-Z0-9]' THEN UPPER(s.Icao) END                         AS IcaoCode,
        NULLIF(NULLIF(LTRIM(RTRIM(s.Callsign)), '\N'), '')                                             AS Callsign,
        NULLIF(NULLIF(LTRIM(RTRIM(s.Country)), '\N'), '')                                              AS SourceCountry,
        CASE WHEN s.Active = 'Y' THEN 1 ELSE 0 END                                                     AS IsActive
    FROM stg.Airlines AS s
)
INSERT INTO dbo.Airlines
    (AirlineId, AirlineName, Alias, IataCode, IcaoCode, Callsign, CountryId, IsActive)
SELECT
    a.AirlineId, a.AirlineName, a.Alias, a.IataCode, a.IcaoCode, a.Callsign,
    c.CountryId,
    a.IsActive
FROM CleanAirlines AS a
LEFT JOIN CountryAliases AS ca
    ON ca.SourceName = a.SourceCountry
LEFT JOIN dbo.Countries AS c
    ON c.CountryName = COALESCE(ca.CountryName, a.SourceCountry)
WHERE a.AirlineId > 0;      -- id -1 is the file's "Unknown" placeholder row, not an airline

/* ---------- Routes ----------
   The inner joins to Airlines and Airports drop routes whose ids are \N (TRY_CONVERT
   gives NULL, and NULL never joins) or point to an airline/airport that is not in the
   other files. */
INSERT INTO dbo.Routes
    (AirlineId, SourceAirportId, DestAirportId, IsCodeshare, Stops, Equipment)
SELECT
    al.AirlineId,
    src.AirportId,
    dst.AirportId,
    CASE WHEN s.Codeshare = 'Y' THEN 1 ELSE 0 END,
    ISNULL(TRY_CONVERT(tinyint, s.Stops), 0),
    NULLIF(NULLIF(LTRIM(RTRIM(s.Equipment)), '\N'), '')
FROM stg.Routes AS s
JOIN dbo.Airlines AS al  ON al.AirlineId  = TRY_CONVERT(int, s.AirlineId)
JOIN dbo.Airports AS src ON src.AirportId = TRY_CONVERT(int, s.SourceAirportId)
JOIN dbo.Airports AS dst ON dst.AirportId = TRY_CONVERT(int, s.DestAirportId)
WHERE src.AirportId <> dst.AirportId;   -- one source row "flies" from an airport to itself

COMMIT TRANSACTION;
GO

/* ---------- Load report: rows in the file vs rows kept ---------- */
SET NOCOUNT ON;

SELECT 'Countries' AS TableName, NULL AS RowsInFile, COUNT(*) AS RowsLoaded, NULL AS RowsRejected
FROM dbo.Countries
UNION ALL
SELECT 'Airports', (SELECT COUNT(*) FROM stg.Airports), COUNT(*), (SELECT COUNT(*) FROM stg.Airports) - COUNT(*)
FROM dbo.Airports
UNION ALL
SELECT 'Airlines', (SELECT COUNT(*) FROM stg.Airlines), COUNT(*), (SELECT COUNT(*) FROM stg.Airlines) - COUNT(*)
FROM dbo.Airlines
UNION ALL
SELECT 'Routes',   (SELECT COUNT(*) FROM stg.Routes),   COUNT(*), (SELECT COUNT(*) FROM stg.Routes) - COUNT(*)
FROM dbo.Routes;

SELECT
    (SELECT COUNT(*) FROM dbo.Airports WHERE IataCode IS NULL)  AS AirportsWithoutIata,
    (SELECT COUNT(*) FROM dbo.Airlines WHERE CountryId IS NULL) AS AirlinesWithoutCountry;
GO
