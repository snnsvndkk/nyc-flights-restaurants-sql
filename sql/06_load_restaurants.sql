/* Staging -> clean tables for the NYC restaurant inspection data.

   The source is denormalized: ONE ROW PER VIOLATION, and every row repeats the
   restaurant columns (name, address, cuisine ...) and the inspection columns
   (date, type, score, grade ...). An inspection without violations still has one row,
   with an empty violation code. This script splits that into three levels:

       Restaurants          one row per CAMIS                              (GROUP BY Camis)
       Inspections          one row per restaurant + date + inspection type
       InspectionViolations one row per violation cited in an inspection

   Cleaning rules:
     - dates arrive as '2025-02-20T00:00:00.000'  -> first 10 characters converted to date
     - borough '0' is a placeholder for "unknown"  -> NULL
     - latitude / longitude 0 mean "not geocoded"  -> NULL
     - a phone that is not exactly 10 digits       -> NULL
     - the same violation description exists in slightly different wordings -> keep the
       most frequently used one per code
     - a few violation rows are exact duplicates   -> collapsed by GROUP BY

   Load order follows the foreign keys. One transaction: all or nothing. */
USE FlightsRestaurantsDB;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;

BEGIN TRANSACTION;

/* ---------- Lookup tables ---------- */
INSERT INTO dbo.Boroughs (BoroughName)
SELECT DISTINCT LTRIM(RTRIM(s.Boro))
FROM stg.RestaurantInspections AS s
WHERE NULLIF(NULLIF(LTRIM(RTRIM(s.Boro)), '0'), '') IS NOT NULL
ORDER BY 1;

INSERT INTO dbo.Cuisines (CuisineName)
SELECT DISTINCT LTRIM(RTRIM(s.CuisineDescription))
FROM stg.RestaurantInspections AS s
WHERE NULLIF(LTRIM(RTRIM(s.CuisineDescription)), '') IS NOT NULL
ORDER BY 1;

/* ---------- Restaurants ----------
   The restaurant columns are identical on every row of the same CAMIS (checked while
   profiling), so MAX() is only a way to collapse the repeated rows into one. */
WITH RestaurantRows AS
(
    SELECT
        TRY_CONVERT(int, s.Camis)                                AS RestaurantId,
        MAX(LTRIM(RTRIM(s.Dba)))                                 AS RestaurantName,
        MAX(NULLIF(LTRIM(RTRIM(s.Boro)), '0'))                   AS BoroughName,
        MAX(LTRIM(RTRIM(s.CuisineDescription)))                  AS CuisineName,
        MAX(NULLIF(LTRIM(RTRIM(s.Building)), ''))                AS Building,
        MAX(NULLIF(LTRIM(RTRIM(s.Street)), ''))                  AS Street,
        MAX(CASE WHEN s.ZipCode LIKE '[0-9][0-9][0-9][0-9][0-9]' THEN s.ZipCode END) AS ZipCode,
        MAX(CASE WHEN s.Phone LIKE REPLICATE('[0-9]', 10) THEN s.Phone END)          AS Phone,
        MAX(NULLIF(TRY_CONVERT(float, s.Latitude), 0))           AS Latitude,
        MAX(NULLIF(TRY_CONVERT(float, s.Longitude), 0))          AS Longitude
    FROM stg.RestaurantInspections AS s
    WHERE TRY_CONVERT(int, s.Camis) IS NOT NULL
    GROUP BY TRY_CONVERT(int, s.Camis)
)
INSERT INTO dbo.Restaurants
    (RestaurantId, RestaurantName, BoroughId, CuisineId, Building, Street, ZipCode, Phone, Latitude, Longitude)
SELECT
    r.RestaurantId,
    ISNULL(NULLIF(r.RestaurantName, ''), N'(name not recorded)'),
    b.BoroughId,
    c.CuisineId,
    r.Building, r.Street, r.ZipCode, r.Phone,
    CONVERT(decimal(9,6), r.Latitude),
    CONVERT(decimal(9,6), r.Longitude)
FROM RestaurantRows AS r
LEFT JOIN dbo.Boroughs AS b ON b.BoroughName = r.BoroughName
LEFT JOIN dbo.Cuisines AS c ON c.CuisineName = r.CuisineName;

/* ---------- Inspections ----------
   Score, grade and action belong to the inspection, not to the violation, so they are
   the same on every row of one inspection. */
INSERT INTO dbo.Inspections
    (RestaurantId, InspectionDate, InspectionType, Action, Score, Grade, GradeDate)
SELECT
    TRY_CONVERT(int, s.Camis),
    TRY_CONVERT(date, LEFT(s.InspectionDate, 10), 23),          -- style 23 = yyyy-mm-dd
    LTRIM(RTRIM(s.InspectionType)),
    MAX(NULLIF(LTRIM(RTRIM(s.Action)), '')),
    MAX(TRY_CONVERT(smallint, s.Score)),
    MAX(NULLIF(LTRIM(RTRIM(s.Grade)), '')),
    MAX(TRY_CONVERT(date, LEFT(s.GradeDate, 10), 23))
FROM stg.RestaurantInspections AS s
WHERE TRY_CONVERT(int, s.Camis) IS NOT NULL
  AND TRY_CONVERT(date, LEFT(s.InspectionDate, 10), 23) IS NOT NULL
  AND NULLIF(LTRIM(RTRIM(s.InspectionType)), '') IS NOT NULL
GROUP BY
    TRY_CONVERT(int, s.Camis),
    TRY_CONVERT(date, LEFT(s.InspectionDate, 10), 23),
    LTRIM(RTRIM(s.InspectionType))
ORDER BY 1, 2, 3;

/* ---------- ViolationCodes ----------
   ROW_NUMBER() ranks the descriptions of each code by how often they are used;
   rank 1 = the most common wording, which becomes the code's description. */
WITH DescriptionUsage AS
(
    SELECT
        LTRIM(RTRIM(s.ViolationCode))        AS ViolationCode,
        LTRIM(RTRIM(s.ViolationDescription)) AS Description,
        ROW_NUMBER() OVER (
            PARTITION BY LTRIM(RTRIM(s.ViolationCode))
            ORDER BY COUNT(*) DESC, LTRIM(RTRIM(s.ViolationDescription))
        ) AS UsageRank
    FROM stg.RestaurantInspections AS s
    WHERE NULLIF(LTRIM(RTRIM(s.ViolationCode)), '') IS NOT NULL
    GROUP BY LTRIM(RTRIM(s.ViolationCode)), LTRIM(RTRIM(s.ViolationDescription))
)
INSERT INTO dbo.ViolationCodes (ViolationCode, Description)
SELECT d.ViolationCode, ISNULL(d.Description, N'(no description)')
FROM DescriptionUsage AS d
WHERE d.UsageRank = 1;

/* ---------- InspectionViolations ----------
   Staging rows find their inspection through the natural key
   (restaurant, date, type). Rows with no violation code (clean inspections) add nothing. */
INSERT INTO dbo.InspectionViolations (InspectionId, ViolationCode, IsCritical)
SELECT
    i.InspectionId,
    LTRIM(RTRIM(s.ViolationCode)),
    MAX(CASE WHEN s.CriticalFlag = 'Critical' THEN 1 ELSE 0 END)
FROM stg.RestaurantInspections AS s
JOIN dbo.Inspections AS i
    ON  i.RestaurantId   = TRY_CONVERT(int, s.Camis)
    AND i.InspectionDate = TRY_CONVERT(date, LEFT(s.InspectionDate, 10), 23)
    AND i.InspectionType = LTRIM(RTRIM(s.InspectionType))
WHERE NULLIF(LTRIM(RTRIM(s.ViolationCode)), '') IS NOT NULL
GROUP BY i.InspectionId, LTRIM(RTRIM(s.ViolationCode));

COMMIT TRANSACTION;
GO

/* ---------- Load report ---------- */
SET NOCOUNT ON;

SELECT 'Boroughs' AS TableName, COUNT(*) AS RowsLoaded FROM dbo.Boroughs
UNION ALL SELECT 'Cuisines',             COUNT(*) FROM dbo.Cuisines
UNION ALL SELECT 'Restaurants',          COUNT(*) FROM dbo.Restaurants
UNION ALL SELECT 'Inspections',          COUNT(*) FROM dbo.Inspections
UNION ALL SELECT 'ViolationCodes',       COUNT(*) FROM dbo.ViolationCodes
UNION ALL SELECT 'InspectionViolations', COUNT(*) FROM dbo.InspectionViolations;

-- Reconciliation: every staging row with a violation code must be represented.
SELECT
    (SELECT COUNT(*) FROM stg.RestaurantInspections)                                  AS RowsInFile,
    (SELECT COUNT(*) FROM stg.RestaurantInspections WHERE ViolationCode IS NOT NULL)  AS RowsWithViolation,
    (SELECT COUNT(*) FROM dbo.InspectionViolations)                                   AS ViolationsLoaded,
    (SELECT COUNT(*) FROM stg.RestaurantInspections WHERE ViolationCode IS NOT NULL)
        - (SELECT COUNT(*) FROM dbo.InspectionViolations)                             AS DuplicateRowsCollapsed;
GO
