/* Creates the database with default file locations and settings. */
USE master;
GO

IF DB_ID(N'FlightsRestaurantsDB') IS NULL
BEGIN
    CREATE DATABASE FlightsRestaurantsDB;
    PRINT 'Created database FlightsRestaurantsDB.';
END
ELSE
    PRINT 'Database FlightsRestaurantsDB already exists.';
GO

-- This is a rebuildable analytics database, so point-in-time recovery is not needed.
-- SIMPLE recovery keeps the transaction log small during the bulk loads.
ALTER DATABASE FlightsRestaurantsDB SET RECOVERY SIMPLE;
GO
