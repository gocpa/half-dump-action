# GoCPA-Half-Dump Script
## Introduction

The gocpa-half-dump.sh script is designed to facilitate the creation of partial database dumps, focusing on recent data. It's particularly useful for managing staging environments or backups where only a subset of the data is required.

## Features

**Database Export:** Exports specified tables or recent data from a production database.

**Database Import:** Imports the exported data into a staging or specified database.

**Table Selection:** Ability to select specific tables for exporting.

**Date-Based Dump:** Options to dump data based on date criteria.

**Error Handling:** Robust error handling for reliable script execution.

## Requirements
* MySQL client installed
* Access to the target MySQL databases
* .sqlpwd file for MySQL authentication

## Installation
Download the script:
```shell
curl -o gocpa-half-dump.sh https://raw.githubusercontent.com/gocpa/half-dump-action/master/gocpa-half-dump.sh
chmod +x gocpa-half-dump.sh
touch .sqlpwd
chmod 600 .sqlpwd
chown $USER:nogroup .sqlpwd
```

## Usage
Run the script with the following command, replacing <options> with your specific parameters:

```shell
./gocpa-half-dump.sh <options>
```
### Options
* `--dumpfile dump.sql` Path to the dump file.
* `--database-from dbname` Source database name.
* `--database-to dbname-dump` Destination database name.
* `--tables-skip "table1 table2"` Tables to skip (space-separated).
* `--tables-bydate "table3 table4"` Tables for which to dump recent data (space-separated).
* `--dump-ago 7` Number of days to include in the dump (default: 7).
* `--maxsize 5120000` Size in bytes, which can be dumped without warning, (default 5120000).

## Additional Notes
Ensure that the .sqlpwd file is properly secured and contains the correct database credentials.
Always test the script in a non-production environment before using it in production to avoid unintended data loss.
