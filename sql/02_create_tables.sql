/* Creates the clean, normalized tables (dbo schema).

   Flights      : Countries -< Airports -< Routes >- Airlines
   Restaurants  : Boroughs / Cuisines -< Restaurants -< Inspections -< InspectionViolations >- ViolationCodes

   The script is re-runnable: it drops the tables first, children before parents,
   because a table cannot be dropped while a foreign key still references it. */
USE FlightsRestaurantsDB;
GO

-- Filtered indexes (used on Airports below) require QUOTED_IDENTIFIER ON. SSMS turns it
-- on by default, the classic sqlcmd does not, so it is set explicitly.
SET QUOTED_IDENTIFIER ON;
GO

DROP TABLE IF EXISTS dbo.InspectionViolations;
DROP TABLE IF EXISTS dbo.Inspections;
DROP TABLE IF EXISTS dbo.ViolationCodes;
DROP TABLE IF EXISTS dbo.Restaurants;
DROP TABLE IF EXISTS dbo.Cuisines;
DROP TABLE IF EXISTS dbo.Boroughs;
DROP TABLE IF EXISTS dbo.Routes;
DROP TABLE IF EXISTS dbo.Airlines;
DROP TABLE IF EXISTS dbo.Airports;
DROP TABLE IF EXISTS dbo.Countries;
GO

/* =====================================================================
   FLIGHTS (OpenFlights)
   ===================================================================== */

-- Country names are repeated on thousands of airport and airline rows in the source
-- files; storing each name once and referencing it by key removes that redundancy.
CREATE TABLE dbo.Countries
(
    CountryId    smallint IDENTITY(1,1) NOT NULL,
    CountryName  nvarchar(60)           NOT NULL,
    CONSTRAINT PK_Countries PRIMARY KEY CLUSTERED (CountryId),
    CONSTRAINT UQ_Countries_CountryName UNIQUE (CountryName)
);

CREATE TABLE dbo.Airports
(
    AirportId     int           NOT NULL,   -- OpenFlights airport id (not an IDENTITY: routes reference it)
    AirportName   nvarchar(100) NOT NULL,
    City          nvarchar(60)  NULL,
    CountryId     smallint      NOT NULL,
    IataCode      char(3)       NULL,       -- e.g. JFK
    IcaoCode      char(4)       NULL,       -- e.g. KJFK
    Latitude      decimal(9,6)  NOT NULL,   -- decimal degrees, 6 decimals is about 0.1 m
    Longitude     decimal(9,6)  NOT NULL,
    AltitudeFt    int           NOT NULL,
    UtcOffset     decimal(4,2)  NULL,       -- hours from UTC; decimal because of offsets like +5.75
    DstCode       char(1)       NULL,       -- OpenFlights daylight-saving rule: E, A, S, O, Z, N, U
    TimeZoneName  varchar(40)   NULL,       -- tz database name, e.g. America/New_York
    CONSTRAINT PK_Airports PRIMARY KEY CLUSTERED (AirportId),
    CONSTRAINT FK_Airports_Countries FOREIGN KEY (CountryId) REFERENCES dbo.Countries (CountryId),
    CONSTRAINT CK_Airports_Latitude  CHECK (Latitude  BETWEEN -90  AND 90),
    CONSTRAINT CK_Airports_Longitude CHECK (Longitude BETWEEN -180 AND 180)
);

-- Codes are optional but must be unique when present. A normal UNIQUE constraint would
-- allow only a single NULL, so these are filtered unique indexes instead.
CREATE UNIQUE NONCLUSTERED INDEX UX_Airports_IataCode ON dbo.Airports (IataCode) WHERE IataCode IS NOT NULL;
CREATE UNIQUE NONCLUSTERED INDEX UX_Airports_IcaoCode ON dbo.Airports (IcaoCode) WHERE IcaoCode IS NOT NULL;
CREATE NONCLUSTERED INDEX IX_Airports_CountryId ON dbo.Airports (CountryId);

CREATE TABLE dbo.Airlines
(
    AirlineId    int           NOT NULL,    -- OpenFlights airline id
    AirlineName  nvarchar(100) NOT NULL,
    Alias        nvarchar(60)  NULL,
    IataCode     char(2)       NULL,        -- not unique: codes are reused once an airline is defunct
    IcaoCode     char(3)       NULL,
    Callsign     nvarchar(60)  NULL,
    CountryId    smallint      NULL,        -- NULL when the source country is missing or not a real country
    IsActive     bit           NOT NULL,
    CONSTRAINT PK_Airlines PRIMARY KEY CLUSTERED (AirlineId),
    CONSTRAINT FK_Airlines_Countries FOREIGN KEY (CountryId) REFERENCES dbo.Countries (CountryId)
);

CREATE NONCLUSTERED INDEX IX_Airlines_CountryId ON dbo.Airlines (CountryId);

-- One row = one airline flying from one airport to another (directional).
CREATE TABLE dbo.Routes
(
    RouteId          int IDENTITY(1,1) NOT NULL,
    AirlineId        int         NOT NULL,
    SourceAirportId  int         NOT NULL,
    DestAirportId    int         NOT NULL,
    IsCodeshare      bit         NOT NULL,  -- 1 = operated by another carrier under this airline's code
    Stops            tinyint     NOT NULL,  -- 0 = direct
    Equipment        varchar(50) NULL,      -- aircraft type codes, informational only
    CONSTRAINT PK_Routes PRIMARY KEY CLUSTERED (RouteId),
    -- Natural key: an airline lists a given origin -> destination only once.
    CONSTRAINT UQ_Routes_Airline_Source_Dest UNIQUE (AirlineId, SourceAirportId, DestAirportId),
    CONSTRAINT FK_Routes_Airlines       FOREIGN KEY (AirlineId)       REFERENCES dbo.Airlines (AirlineId),
    CONSTRAINT FK_Routes_SourceAirport  FOREIGN KEY (SourceAirportId) REFERENCES dbo.Airports (AirportId),
    CONSTRAINT FK_Routes_DestAirport    FOREIGN KEY (DestAirportId)   REFERENCES dbo.Airports (AirportId),
    CONSTRAINT CK_Routes_DifferentAirports CHECK (SourceAirportId <> DestAirportId)
);

-- SQL Server does not index foreign key columns automatically. Routes is joined and
-- counted by departure airport and by arrival airport in almost every query.
CREATE NONCLUSTERED INDEX IX_Routes_SourceAirportId ON dbo.Routes (SourceAirportId);
CREATE NONCLUSTERED INDEX IX_Routes_DestAirportId   ON dbo.Routes (DestAirportId);
GO

/* =====================================================================
   RESTAURANTS (NYC DOHMH inspection results)
   The source file is one wide row per violation, repeating the restaurant
   and inspection columns every time. It is split into:
     restaurant -> inspection -> violation cited in that inspection
   ===================================================================== */

CREATE TABLE dbo.Boroughs
(
    BoroughId    tinyint IDENTITY(1,1) NOT NULL,
    BoroughName  nvarchar(20)          NOT NULL,
    CONSTRAINT PK_Boroughs PRIMARY KEY CLUSTERED (BoroughId),
    CONSTRAINT UQ_Boroughs_BoroughName UNIQUE (BoroughName)
);

CREATE TABLE dbo.Cuisines
(
    CuisineId    smallint IDENTITY(1,1) NOT NULL,
    CuisineName  nvarchar(50)           NOT NULL,
    CONSTRAINT PK_Cuisines PRIMARY KEY CLUSTERED (CuisineId),
    CONSTRAINT UQ_Cuisines_CuisineName UNIQUE (CuisineName)
);

CREATE TABLE dbo.Restaurants
(
    RestaurantId    int           NOT NULL, -- CAMIS: the permanent id DOHMH gives each establishment
    RestaurantName  nvarchar(150) NOT NULL, -- "DBA" (doing business as) in the source
    BoroughId       tinyint       NULL,     -- NULL when the source borough is the placeholder '0'
    CuisineId       smallint      NULL,
    Building        nvarchar(20)  NULL,
    Street          nvarchar(100) NULL,
    ZipCode         char(5)       NULL,     -- char, not int: a zip is a label, and can start with 0
    Phone           char(10)      NULL,
    Latitude        decimal(9,6)  NULL,
    Longitude       decimal(9,6)  NULL,
    CONSTRAINT PK_Restaurants PRIMARY KEY CLUSTERED (RestaurantId),
    CONSTRAINT FK_Restaurants_Boroughs FOREIGN KEY (BoroughId) REFERENCES dbo.Boroughs (BoroughId),
    CONSTRAINT FK_Restaurants_Cuisines FOREIGN KEY (CuisineId) REFERENCES dbo.Cuisines (CuisineId)
);

CREATE NONCLUSTERED INDEX IX_Restaurants_BoroughId ON dbo.Restaurants (BoroughId);
CREATE NONCLUSTERED INDEX IX_Restaurants_CuisineId ON dbo.Restaurants (CuisineId);

CREATE TABLE dbo.Inspections
(
    InspectionId    int IDENTITY(1,1) NOT NULL,
    RestaurantId    int           NOT NULL,
    InspectionDate  date          NOT NULL,
    InspectionType  nvarchar(100) NOT NULL, -- e.g. 'Cycle Inspection / Initial Inspection'
    Action          nvarchar(200) NULL,     -- what DOHMH did, e.g. 'Violations were cited ...'
    Score           smallint      NULL,     -- violation points: lower is better
    Grade           char(1)       NULL,     -- A / B / C, or N, Z, P = not yet graded / pending
    GradeDate       date          NULL,
    CONSTRAINT PK_Inspections PRIMARY KEY CLUSTERED (InspectionId),
    -- Natural key. It also provides the index on RestaurantId for the foreign key.
    CONSTRAINT UQ_Inspections_Restaurant_Date_Type UNIQUE (RestaurantId, InspectionDate, InspectionType),
    CONSTRAINT FK_Inspections_Restaurants FOREIGN KEY (RestaurantId) REFERENCES dbo.Restaurants (RestaurantId),
    CONSTRAINT CK_Inspections_Score CHECK (Score >= 0)
);

CREATE TABLE dbo.ViolationCodes
(
    ViolationCode  varchar(10)    NOT NULL, -- e.g. 04L
    Description    nvarchar(1000) NOT NULL,
    CONSTRAINT PK_ViolationCodes PRIMARY KEY CLUSTERED (ViolationCode)
);

-- Junction table for the many-to-many between inspections and violation codes.
-- IsCritical is stored here and not on ViolationCodes because in the source the same
-- code (09A) is flagged critical in some citations and not critical in others.
CREATE TABLE dbo.InspectionViolations
(
    InspectionId   int         NOT NULL,
    ViolationCode  varchar(10) NOT NULL,
    IsCritical     bit         NOT NULL,
    CONSTRAINT PK_InspectionViolations PRIMARY KEY CLUSTERED (InspectionId, ViolationCode),
    CONSTRAINT FK_InspectionViolations_Inspections    FOREIGN KEY (InspectionId)  REFERENCES dbo.Inspections (InspectionId),
    CONSTRAINT FK_InspectionViolations_ViolationCodes FOREIGN KEY (ViolationCode) REFERENCES dbo.ViolationCodes (ViolationCode)
);

CREATE NONCLUSTERED INDEX IX_InspectionViolations_ViolationCode ON dbo.InspectionViolations (ViolationCode);
GO

PRINT 'Created 10 tables in FlightsRestaurantsDB.';
GO
