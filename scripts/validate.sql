/*
    Post-migration validation.

    Run this against each local database and then against its Azure cloud copy, and compare the results.
    If object counts and row counts match, the migration carried everything over. 

    In SSMS: Connect to the source (local) instance, pick the database, run it. Then connect to your 
    Azure SQL Server instance, pick the same databases, run it again. Compare A to B.
*/

/*-------------------------------------------
1.) Object counts by type (tables, views, procedures, functions, etc.)
    A mismatch here means schema objects did not all come across. 
*/-------------------------------------------
Select type_desc, 
    count(*) as object_count
from sys.objects
where is_ms_shipped = 0
group by type_desc 
order by type_desc;

/*-------------------------------------------
2.) Row count per user table (read from partition metadata -- fast and exact enough for a parity check)
    A mismatch means data did not fully load.
*/-------------------------------------------

Select s.name as schema_name,
    t.name as table_name,
    sum(p.rows) as row_count
from sys.tables t
join sys.schemas s on s.schema_id = t.schema_id
join sys.partitions p on p.object_id = t.object_id
                        and p.index_id in (0,1)
group by s.name, t.name
order by s.name, t.name;

/*-------------------------------------------
3.) Grand total rows across the whole database -- one number to eyeball first. 
*/-------------------------------------------
Select sum(p.rows) as total_rows_in_database
from sys.tables t
join sys.partitions p on p.object_id = t.object_id
                        and p.index_id in (0,1);