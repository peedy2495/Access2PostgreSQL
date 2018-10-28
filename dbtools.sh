#!/bin/bash

#dbtools written by Peter Mark

path=$1
delim=','                                   #define column-delimiter within .csv-files, here

function conv_chars () {
  pattern="$path/*.csv"                     #search pattern for .csv-files
  for file in $pattern; do                  #process every .csv file in given path
    modfile="$path/mod_$(basename $file)"   #append "mod_" to filename
    enc="$(file -bi $file |awk -F '=' '{print $2}')"  #determine current encoding
    if [ "$enc" != utf-8 ]; then
      if [ "$enc" = binary ]; then
        echo "Can\'t convert binary Files! Skipping $file ..."
      elif [ "$enc" = unknown-8bit ]; then
        iconv -f iso-8859-1 -t utf-8 < $file > $modfile \
          || echo "Conversion failed! Skipping $file"
      else
        iconv -t utf-8 < $file > $modfile \
          || echo "Conversion failed! Skipping $file"
      fi
    else
      cp $file $modfile                     #oh, file ist already in utf-8. Well, then make a copy :-)
    fi
  done
}

function gen_sql () {
  pattern="$path/mod_*.csv"                 #search pattern for translated files (utf-8)
  for file in $pattern; do                  #process every mod_*.csv file in given path
    sqlfile="${file%.csv}.sql"
    filename=$(basename $file)
    tablename="${filename%.csv}"
    cols=$(head -n1 $file)                  #determine number of cloumns ...
    ncols=$(echo $cols | sed "s/[^$delim]//g" | wc -c)
    echo "Table $(basename $file) has $ncols colunms"
    echo -n "Schema name: "
    read schema
    echo -ne "CREATE TABLE $schema.\"$tablename\"\n(\n" > $sqlfile
    oifs=$IFS                               #saving original IFS
    IFS=$"$delim"                           #setting IFS to column delimiter
      for col in $cols; do
        #Comparsion Datatypes
        #M$-Access  Postgres
        #Text       varchar(255)
        #Byte       n.a.
        #INTEGER    smallint
        #LONG       integer
        #Single     float
        #Double     real
        #Currency   n.a.
        #Autonumber integer
        #Date/Time  varchar(64)
        #Yes/No     boolean
        #OLE-Object n.a.
        #Hyperlink  varchar(255)
        #LookupWizard n.a.
        PS3="Enter PostgreSQL-Datatype for $(basename $file).$col :"
        dtypes=("character varying(255)" "integer" "smallint" "real" "double precision" "boolean" )
        select dtype in "${dtypes[@]}"; do
          case $dtype in
            *)
              if  [[ "$dtype" != "" ]]; then
                echo -e "$(basename $file).$col :\t$dtype"
                echo -e "\t\"$col\" $dtype," >> $sqlfile
                break
              else
                echo "Missmatch: Selectetd key off menu!"
              fi
            ;;
          esac
        done
      done
      head -c -2 $sqlfile > "$sqlfile.tmp"
      mv "$sqlfile.tmp" $sqlfile
      echo -e "\n)\n\nWITH (\n\tOIDS = FALSE\n);\n\nALTER TABLE $schema.\"$tablename\"\n\tOWNER to postgres;" >> $sqlfile
      IFS=$ofis                               #restore original IFS
  done
}

function fix_cols () {
  pattern="$path/mod_*.csv"                   #search pattern for translated files (utf-8)
  line="1"
  for file in $pattern; do                    #process every mod_*.csv file in given path
    lines=$(wc -l $file|awk -F ' ' '{print $1}')
    cols=$(head -n1 $file)
    ncols=$(echo $cols | sed "s/[^,]//g" | wc -c)
    echo "Table $(basename $file) has $ncols colunms and $lines lines"
    echo "checking consistency ..."
    echo "" > $path/data_$(basename $file)    #create or overwrite to empty File
    linenum=1
    while read line; do                       #process file linie by line
      inquote="false"                         #flag for skipping delimiter chars within string-quotes
      ndelim=0
      i=0                                     #counter for chars in line
      while (( i++ < ${#line} )); do          #process line char by char
        char=$(expr substr "$line" $i 1)
        if [ "$char" = \" ] && [ "$inquote" = true ]; then
          inquote="false"
        elif [ "$char" = \" ] && [ "$inquote" = false ]; then
          inquote="true"
        elif [ "$char" = "$delim" ] && [ "$inquote" = false ]; then
          ((ndelim++))
        fi
      done
      diff=$(( ncols-ndelim-1 ))              #deviant number of columns to headline
      echo "Line $linenum column difference: $diff"
      while [ $diff -gt 0 ]; do               #append deviant columns
        line=$line$delim
        ((diff--))
      done
      if [ $linenum -ne 1 ]; then             #append finalized line without header to data-file
        echo $line >> $path/data_$(basename $file)
      fi
      ((linenum++))
    done <$file
  done
}

function pg_import () {
  echo -n "Database name: "
  read db
  echo -n "Host: "
  read host
  echo -n "User: "
  read user
  echo -n "Pasword: "
  read pass
  pattern="$path/mod_*.sql"                   #search pattern for translated files (utf-8)
  line="1"
  for file in $pattern; do                    #process every mod_*.csv file in given path
    echo "importing $file ..."
    PGPASSWORD=$pass psql -h $host -d $db -U $user -p 5432 -a -q -f $file
  done
}

function chk_path () {                        #outsourced routine to check path-existence
  if [ ! -d $path ]; then
    echo "$path does not exist! Exit!"
    exit 1
  echo "path is: $path"
  fi
}

while [ -n "$1" ]; do                         #argument processing without need of fixed sequence
  case "$1" in
    src=*)                                    #sourcepath
      path=$(echo $1 | awk -F '=' '{print $2}')
      ;;
    charconv)                                 #convert files to utf-8
      chk_path
      conv_chars
      ;;
    fixcols)                                  #ensure consistency of column count in data-fileds
      chk_path
      fix_cols
      ;;
    mksql)                                    #generate sql-statements for table creation in postgres
      chk_path
      gen_sql
      ;;
    pgimport)                                 #fire the sql-statements against the database :-)
      chk_path
      pg_import
      ;;
    *)
      echo "Wrong argument: $1 !"
      echo $"Usage: $0 {src=[path]|charconv|mksql|pgimport}"
      exit 1
    esac
  shift
done
