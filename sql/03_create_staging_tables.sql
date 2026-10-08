/* Staging tables: a 1:1 copy of each raw file, every column as text.

   Loading is done in two steps (ELT):
     1. BULK INSERT the raw files into these tables without any conversion, so a
        single bad value can never make the file load fail          (04_load_staging.sql)
     2. Clean, type-convert and normalize with plain INSERT ... SELECT
                                              (05_load_openflights.sql, 06_load_restaurants.sql)

   Column order must match the column order of the files. */
USE FlightsRestaurantsDB;
GO

IF SCHEMA_ID(N'stg') IS NULL
    EXEC (N'CREATE SCHEMA stg AUTHORIZATION dbo;');
GO

DROP TABLE IF EXISTS stg.Airports;
DROP TABLE IF EXISTS stg.Airlines;
DROP TABLE IF EXISTS stg.Routes;
DROP TABLE IF EXISTS stg.RestaurantInspections;
GO

-- airports.dat (no header row)
CREATE TABLE stg.Airports
(
    AirportId   nvarchar(200) NULL,
    Name        nvarchar(200) NULL,
    City        nvarchar(200) NULL,
    Country     nvarchar(200) NULL,
    Iata        nvarchar(200) NULL,
    Icao        nvarchar(200) NULL,
    Latitude    nvarchar(200) NULL,
    Longitude   nvarchar(200) NULL,
    AltitudeFt  nvarchar(200) NULL,
    UtcOffset   nvarchar(200) NULL,
    Dst         nvarchar(200) NULL,
    TzDatabase  nvarchar(200) NULL,
    Type        nvarchar(200) NULL,
    Source      nvarchar(200) NULL
);

-- airlines.dat (no header row)
CREATE TABLE stg.Airlines
(
    AirlineId   nvarchar(200) NULL,
    Name        nvarchar(200) NULL,
    Alias       nvarchar(200) NULL,
    Iata        nvarchar(200) NULL,
    Icao        nvarchar(200) NULL,
    Callsign    nvarchar(200) NULL,
    Country     nvarchar(200) NULL,
    Active      nvarchar(200) NULL
);

-- routes.dat (no header row)
CREATE TABLE stg.Routes
(
    AirlineCode       nvarchar(200) NULL,
    AirlineId         nvarchar(200) NULL,
    SourceAirportCode nvarchar(200) NULL,
    SourceAirportId   nvarchar(200) NULL,
    DestAirportCode   nvarchar(200) NULL,
    DestAirportId     nvarchar(200) NULL,
    Codeshare         nvarchar(200) NULL,
    Stops             nvarchar(200) NULL,
    Equipment         nvarchar(200) NULL
);

-- nyc_restaurant_inspections.csv (header row; one row per violation cited in an inspection).
-- Column order = the $select list in scripts/download_data.ps1.
CREATE TABLE stg.RestaurantInspections
(
    Camis                nvarchar(50)   NULL,
    Dba                  nvarchar(500)  NULL,
    Boro                 nvarchar(50)   NULL,
    Building             nvarchar(100)  NULL,
    Street               nvarchar(500)  NULL,
    ZipCode              nvarchar(50)   NULL,
    Phone                nvarchar(50)   NULL,
    CuisineDescription   nvarchar(200)  NULL,
    InspectionDate       nvarchar(50)   NULL,
    InspectionType       nvarchar(200)  NULL,
    Action               nvarchar(500)  NULL,
    Score                nvarchar(50)   NULL,
    Grade                nvarchar(50)   NULL,
    GradeDate            nvarchar(50)   NULL,
    ViolationCode        nvarchar(50)   NULL,
    ViolationDescription nvarchar(4000) NULL,
    CriticalFlag         nvarchar(50)   NULL,
    Latitude             nvarchar(50)   NULL,
    Longitude            nvarchar(50)   NULL
);
GO
