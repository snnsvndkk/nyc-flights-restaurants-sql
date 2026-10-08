/* Row count of every clean table - printed at the end of a build. */
USE FlightsRestaurantsDB;
GO

SET NOCOUNT ON;

SELECT 'Countries' AS TableName, COUNT(*) AS [RowCount] FROM dbo.Countries
UNION ALL SELECT 'Airports',             COUNT(*) FROM dbo.Airports
UNION ALL SELECT 'Airlines',             COUNT(*) FROM dbo.Airlines
UNION ALL SELECT 'Routes',               COUNT(*) FROM dbo.Routes
UNION ALL SELECT 'Boroughs',             COUNT(*) FROM dbo.Boroughs
UNION ALL SELECT 'Cuisines',             COUNT(*) FROM dbo.Cuisines
UNION ALL SELECT 'Restaurants',          COUNT(*) FROM dbo.Restaurants
UNION ALL SELECT 'Inspections',          COUNT(*) FROM dbo.Inspections
UNION ALL SELECT 'ViolationCodes',       COUNT(*) FROM dbo.ViolationCodes
UNION ALL SELECT 'InspectionViolations', COUNT(*) FROM dbo.InspectionViolations;
GO
