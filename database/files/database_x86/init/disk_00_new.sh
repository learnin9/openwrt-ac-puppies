#!/bin/sh 
eexit () {
	echo "$*" 1>&2
	exit 1
}

work_dir=`grep -E "work_dir[ \t]+=" ../config.lua  | awk -F\" '{print $2}'`
disk_dir=`grep -E "disk_dir[ \t]+=" ../config.lua  | awk -F\" '{print $2}'`
echo $disk_dir | grep -E "^/" >/dev/null 2>&1
test $? -eq 0 || eexit "invalid disk_dir $disk_dir"
mkdir -p $disk_dir

diskdb=$disk_dir/disk.db.tgz
workdb=$work_dir/disk.db
rm -f $workdb

if [ -e $diskdb ]; then 
	tar -xzf $diskdb -C $work_dir
	test $? -eq 0 || eexit "extract backup fail"	
else
	sqlite3 $workdb "select 1" >/dev/null 2>&1
	test $? -eq 0 || eexit "missing $workdb"
fi

test -e $workdb || eexit "init $workdb fail"

## following mysql 
sql="create database if not exists disk"
mysql -uroot -pwjrc0409 -e "$sql"
test $? -eq 0 || eexit "sql fail $sql"

