REM Script for creating multiple consecutive Oracle GLOBAL AWR Reports for PDB
REM Changes done by Rahul Kurkute Date 24 April 2025
REM Creates an output SQL script which, when run, will generate all GLOBAL AWR Reports
REM between the specificed start and end snapshot IDs, for all instances
REM
REM For educational purposes only - no warranty is provided
REM Test thoroughly - use at your own risk
REM Changes done by Rahul Kurkute Date 24 April 2025
REM
set feedback off
set echo off
set verify off
set timing off
-- Set AWR_FORMAT to "text" or "html"
define AWR_FORMAT = 'html'
define DEFAULT_OUTPUT_FILENAME = 'awr-generate.sql'
define NO_ADDM = 0
-- Get values for dbid and inst_num before calling awrinput.sql
set echo off heading on
column inst_num heading "Inst Num" new_value inst_num format 99999;
column inst_name heading "Instance" new_value inst_name format a12;
column db_name heading "DB Name" new_value db_name format a12;
column dbid heading "DB Id" new_value dbid format 9999999999 just c;
alter session set "_push_join_predicate"=false;
alter session set "_optimizer_push_pred_cost_based" = false;

prompt 
prompt Script for creating multiple consecutive Oracle GLOBAL AWR Reports for PDB
prompt Current Instance
prompt ~~~~~~~~~~~~~~~~
select d.dbid dbid
 , d.name db_name
 , i.instance_number inst_num
 , i.instance_name inst_name
 from v$pdbs d,
 v$instance i;
-- Call the Oracle common input script to setup start and end snap ids
@@?/rdbms/admin/awrinput.sql
-- Ask the user for the name of the output script
prompt
prompt Specify output script name
prompt ~~~~~~~~~~~~~~~~~~~~~~~~~~
prompt This script produces output in the form of another SQL script
prompt The output script contains the commands to generate the AWR Reports
prompt
prompt The default output file name is &DEFAULT_OUTPUT_FILENAME
prompt To accept this name, press <return> to continue, otherwise enter an alternative
prompt
set heading off
column outfile_name new_value outfile_name noprint;
select 'Using the output file name ' || nvl('&&outfile_name','&DEFAULT_OUTPUT_FILENAME')
, nvl('&&outfile_name','&DEFAULT_OUTPUT_FILENAME') outfile_name
from sys.dual;
set linesize 800
set serverout on
set termout off
-- spool to outputfile
spool &outfile_name
-- write script header comments
prompt REM Temporary script created by awr-generator.sql
prompt REM Used to create multiple AWR reports between two snapshots
select 'REM Created by user '||user||' on '||sys_context('userenv', 'host')||' at '||to_char(sysdate, 'DD-MON-YYYY HH24:MI') from dual;
set heading on
-- Begin iterating through snapshots and generating reports
DECLARE
c_dbid CONSTANT NUMBER := :dbid;
c_inst_num CONSTANT NUMBER := :inst_num;
c_start_snap_id CONSTANT NUMBER := :bid;
c_end_snap_id CONSTANT NUMBER := :eid;
c_awr_options CONSTANT NUMBER := &&NO_ADDM;
c_report_type CONSTANT CHAR(4):= '&&AWR_FORMAT';
v_awr_reportname VARCHAR2(100);
v_report_suffix CHAR(5);
v_db_name varchar2(10);
CURSOR c_snapshots IS
select inst_num, start_snap_id, end_snap_id
from (
select s.instance_number as inst_num,
s.snap_id as start_snap_id,
lead(s.snap_id,1,null) over (partition by s.instance_number order by s.snap_id) as end_snap_id
from dba_hist_snapshot s
where s.dbid = c_dbid
and s.snap_id >= c_start_snap_id
and s.snap_id <= c_end_snap_id
)
where end_snap_id is not null
order by inst_num, start_snap_id;
BEGIN
dbms_output.put_line('');
dbms_output.put_line('prompt Beginning AWR Generation...');
dbms_output.put_line('set heading off feedback off lines 800 pages 5000 trimspool on trimout on');
-- Determine report type (html or text)
IF c_report_type = 'html' THEN
v_report_suffix := '.html';
ELSE
v_report_suffix := '.txt';
END IF;
 
select name into v_db_name from v$pdbs;
-- Iterate through snapshots
FOR cr_snapshot in c_snapshots
LOOP
-- Construct filename for AWR report
v_awr_reportname := 'gawrgrpt_'||v_db_name||cr_snapshot.inst_num||'_'||cr_snapshot.start_snap_id||'_'||cr_snapshot.end_snap_id||v_report_suffix;
dbms_output.put_line('prompt Creating GLOBAL AWR Report for '||v_db_name|| ' PDB ' ||v_awr_reportname
||' for instance number '||cr_snapshot.inst_num||' snapshots '||cr_snapshot.start_snap_id||' to '||cr_snapshot.end_snap_id);
dbms_output.put_line('prompt');
-- Disable terminal output to stop AWR text appearing on screen
dbms_output.put_line('set termout off');
-- Set spool to create AWR report file
dbms_output.put_line('spool '||v_awr_reportname);
-- call the table function to generate the report
IF c_report_type = 'html' THEN
dbms_output.put_line('select output from table(dbms_workload_repository.AWR_GLOBAL_REPORT_HTML('
||c_dbid||','||cr_snapshot.inst_num||','||cr_snapshot.start_snap_id||','||cr_snapshot.end_snap_id||','||c_awr_options||'));');
ELSE
dbms_output.put_line('select output from table(dbms_workload_repository.AWR_GLOBAL_REPORT_TEXT('
||c_dbid||','||cr_snapshot.inst_num||','||cr_snapshot.start_snap_id||','||cr_snapshot.end_snap_id||','||c_awr_options||'));');
END IF;
dbms_output.put_line('spool off');
-- Enable terminal output having finished generating AWR report
dbms_output.put_line('set termout on');
END LOOP;
dbms_output.put_line('set heading on feedback 6 lines 100 pages 45');
dbms_output.put_line('prompt AWR Generation Complete');
-- EXCEPTION HANDLER?
END;
/
spool off
set termout on
prompt
prompt Script written to &outfile_name - check and run in order to generate AWR reports...
prompt
--clear columns sql
undefine outfile_name
undefine AWR_FORMAT
undefine DEFAULT_OUTPUT_FILENAME
undefine NO_ADDM
undefine OUTFILE_NAME
set feedback 6 verify on lines 100 pages 45	
