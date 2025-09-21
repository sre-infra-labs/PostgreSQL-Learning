
/* 01
Create dbname= stackoverflow
create user and give required permissions 
usr_report_rw → to create / delete schema and tables in all above database for user
usr_report_ro → to read the data
*/
create database stackoverflow;
CREATE role usr_report_rw WITH login PASSWORD 'My$tr0ngPwdHere';
CREATE role usr_report_ro WITH login PASSWORD 'My$tr0ngPwdHere2';

/* Permissions for READONLY role */
GRANT CONNECT ON DATABASE stackoverflow TO usr_report_ro;
GRANT USAGE ON SCHEMA public TO usr_report_ro;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO usr_report_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO usr_report_ro;

/* Permissions for READWRITE role */
GRANT CONNECT, CREATE, TEMP ON DATABASE stackoverflow TO usr_report_rw;
GRANT USAGE, CREATE ON SCHEMA public TO usr_report_rw;
GRANT ALL PRIVILEGES ON DATABASE stackoverflow TO usr_report_rw;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO usr_report_rw;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO usr_report_rw;