/* Bulk-loads the four raw files into the staging tables.

   $(RawDataDir) is a sqlcmd scripting variable - scripts/load_data.ps1 passes it:
       sqlcmd ... -v RawDataDir="C:\path\to\repo\data\raw" -i sql\04_load_staging.sql
   To run this file in SSMS instead, turn on Query > SQLCMD Mode and add a first line:
       :setvar RawDataDir "C:\path\to\repo\data\raw"

   BULK INSERT options used:
     FORMAT = 'CSV'       RFC 4180 parsing: quoted fields may contain commas and "" quotes
     CODEPAGE = '65001'   the files are UTF-8 (airport names, the degree sign in violations)
     ROWTERMINATOR 0x0a   the files use Unix (LF) line endings
     TABLOCK              table lock -> minimally logged, faster load

   With Windows authentication SQL Server reads the file using the caller's own
   Windows account, so the service account needs no access to the repo folder. */
USE FlightsRestaurantsDB;
GO

SET NOCOUNT ON;

TRUNCATE TABLE stg.Airports;
TRUNCATE TABLE stg.Airlines;
TRUNCATE TABLE stg.Routes;
TRUNCATE TABLE stg.RestaurantInspections;
GO

BULK INSERT stg.Airports
FROM '$(RawDataDir)\airports.dat'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a',
      CODEPAGE = '65001', TABLOCK);

BULK INSERT stg.Airlines
FROM '$(RawDataDir)\airlines.dat'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a',
      CODEPAGE = '65001', TABLOCK);

BULK INSERT stg.Routes
FROM '$(RawDataDir)\routes.dat'
WITH (FORMAT = 'CSV', FIELDQUOTE = '"', FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a',
      CODEPAGE = '65001', TABLOCK);

-- FIRSTROW = 2 skips the header row.
BULK INSERT stg.RestaurantInspections
FROM '$(RawDataDir)\nyc_restaurant_inspections.csv'
WITH (FORMAT = 'CSV', FIRSTROW = 2, FIELDQUOTE = '"', FIELDTERMINATOR = ',', ROWTERMINATOR = '0x0a',
      CODEPAGE = '65001', TABLOCK);
GO

SELECT 'stg.Airports'              AS StagingTable, COUNT(*) AS RowsLoaded FROM stg.Airports
UNION ALL SELECT 'stg.Airlines',              COUNT(*) FROM stg.Airlines
UNION ALL SELECT 'stg.Routes',                COUNT(*) FROM stg.Routes
UNION ALL SELECT 'stg.RestaurantInspections', COUNT(*) FROM stg.RestaurantInspections;
GO
