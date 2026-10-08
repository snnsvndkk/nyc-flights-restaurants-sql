# Flights & Restaurants SQL Project

T-SQL portfolio project on Microsoft SQL Server, built on two real public datasets:
OpenFlights (airports, airlines, routes) and NYC restaurant inspection results.

Full documentation is added at the end of the build.

## Layout

| Folder     | Contents                                                        |
|------------|-----------------------------------------------------------------|
| `scripts/` | PowerShell: download data, build/reset the database, verify     |
| `sql/`     | Database, table and load (staging -> clean tables) scripts      |
| `queries/` | One numbered `.sql` file per business question                  |
| `views/`   | Reusable views                                                  |
| `data/raw/`| Downloaded source files (git-ignored)                           |
