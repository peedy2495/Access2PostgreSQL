# Access2PostgreSQL

Toolset for exported M$-Access files to import into Posgres-Database

Usage:
keywords will be sequenced in written argument order.

Keywords:
src=[path] path to the .csv-files
charconf  convert to utf-8
fixcols   fix number of cols in datafield (append missing delimiters)
mksql     create sql-file for table-definition
pgimport  import sql-file into the database
