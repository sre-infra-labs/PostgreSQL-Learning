
# Extending the Database - The Extension Ecosystem
-----------------------------------------------------

-> An extension is a packaged set of files that can be installed in the cluster
    in order to provide more functionalities.

-> The extensions are installed in the database and not in the cluster.

-> The extensions are managed strictly through specific commands that install, deploy,
    load, and upgrade the extension as a whole.

-> The main aim of the extension is to provide a common interface for administrating
    new features.

-> Default installed "contrib" package provides a set of extensions that are
    maintained by the PostgreSQL developers.

-> Extensions are published through a global repository called "PGXN" (PostgreSQL Extension Network).


The Extension Ecosystem
------------------------

-> The PGXN can be considered as having following functions -
    -> A search engine
    -> An extension package manager
    -> An application programming interface (API)
    -> A client tool

-> A search engine allows users to search the PGXN repository for extensions.
-> An Extension package manager allows users to download and install extensions.
-> An application programming interface (API) defines how applications can interact with the
    package manager and search engine, and therefore how a client can be built.

-> There are 2 main clients available for PGXN -
    -> The pgxn client
    -> The PGXN website

-> PostgreSQL Extension System (PGXS) defines basic set of rules that an extension must follow.

-> PGXS provides a sample makefile that every extension should use to provide a set of common
    functionalities to install, upgrade, and remove the extension.

-> To find the sample makefile

|------------$ pg_config --pgxs
/usr/lib/postgresql/16/lib/pgxs/src/makefiles/pgxs.mk


Extension Components
-----------------------------------------------------------

-> The "control file" defines metadata of extension and is used to install, upgrade, and remove
    the extension.

-> The "script file" is a SQL file that contains statements to create database objects that are
    required by the extension.

-> The script file can also load other files that complete the extension, like a shared library.

-> When asked to install an extension, the system inspects the control file to check if its already installed,
    and if not, it installs the extension by executing the script file in "share directory".

-> To find share directory of the cluster, use the following command -

|------------$ pg_config --sharedir
/usr/share/postgresql/16

-> The extension must be selectively installed in every database that needs it.

-> If an extension is need for all future databases, then it should be installed in the template database.


The Control File
--------------------------------------------------------------

-> The control file is a text file where we specify "directives", which are instructions and metadata
    to let PostgreSQL handle the extension installation.

-> Each directive has a name and a value.

-> The most common directives are as follows-

# check/install contrib package
dpkg -l | grep postgresql-contrib  # Debian/Ubuntu
rpm -qa | grep postgresql-contrib  # RHEL/CentOS

sudo apt install postgresql-contrib  # Debian/Ubuntu
sudo apt install postgresql-plperl
sudo yum install postgresql-contrib  # RHEL/CentOS


-- check available extensions
SELECT * FROM pg_available_extensions WHERE name LIKE '%contrib%';

-- List installed extensions
select * from pg_extension;




*/ 

