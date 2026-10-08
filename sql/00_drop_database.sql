/* Drops FlightsRestaurantsDB if it exists (used by scripts/reset.ps1).
   SINGLE_USER WITH ROLLBACK IMMEDIATE disconnects any open sessions (for example
   an SSMS query window), otherwise DROP DATABASE fails with "database is in use". */
USE master;
GO

IF DB_ID(N'FlightsRestaurantsDB') IS NOT NULL
BEGIN
    ALTER DATABASE FlightsRestaurantsDB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE FlightsRestaurantsDB;
    PRINT 'Dropped database FlightsRestaurantsDB.';
END
ELSE
    PRINT 'Database FlightsRestaurantsDB does not exist - nothing to drop.';
GO
