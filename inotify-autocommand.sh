#!/bin/bash

# https://github.com/norgeous/inotify-autocommand

# this script needs 'jshon' and 'inotify-tools' to run, you can install these with:
# sudo apt-get install jshon inotify-tools

OPTIND=1		 # Reset in case getopts has been used previously in the shell.
verbose=0
json_config_file=""

while getopts "h?vc:" opt; do
	case "$opt" in
	h|\?)
		show_help
		exit 0
		;;
	v)
		let "verbose++"
		;;
	c)
		json_config_file="$OPTARG"
		;;
	esac
done
shift $((OPTIND-1))
[ "$1" = "--" ] && shift

# logging function
# logthis 0 "always shown"
# logthis 1 "needs -v"
# logthis 0 "causes exit 0" exit
log_file="/dev/null"
logthis () { [ "$verbose" -ge "$1" ] && echo "[$(date '+%d/%m/%Y %H:%M:%S')] $2" | tee -a $log_file; [ "$3" = "exit" ] && exit 0; }

# check useage and that config exists
[[ "$@" != "" ]] && logthis 0 "useage: bash inotify-autocommand.sh -c config.json" exit
[ ! -e "$json_config_file" ] && logthis 0 "no config file found, useage inotify-autocommand.sh -c config.json" exit
JSONCONFIGSTRING=$(cat $json_config_file)
config_log_file=$(echo $JSONCONFIGSTRING | jshon -QC -e "logfile" -u)
[ $config_log_file = "null" ] && log_file="/dev/null"
touch "$config_log_file"
[ ! -f "$config_log_file" ] && logthis 0 "the logfile is not a file" exit
[ -f "$config_log_file" ] && log_file=$config_log_file

logthis 0 "---------------------------------------------------"
logthis 0 "Starting"
logthis 0 "verbose=$verbose, json_config_file='$json_config_file', log_file='$log_file'"
logthis 0 "evaluating config json..."

# Extract values from json config with jshon and cache in assoc array called JOBS
declare -A JOBS
NUMBEROFJOBS=$(echo $JSONCONFIGSTRING | jshon -QC -e "jobs" -l)
for (( job_index=0; job_index<$NUMBEROFJOBS; job_index++ )); do
	NUMBEROFPATHS=$(echo $JSONCONFIGSTRING | jshon -QC -e "jobs" -e $job_index -e "paths" -l)
	JOBS[job$job_index,pathlength]=$NUMBEROFPATHS
	for (( path_index=0; path_index<$NUMBEROFPATHS; path_index++ )); do
		JOBPATH=$(echo $JSONCONFIGSTRING | jshon -QC -e "jobs" -e $job_index -e "paths" -e $path_index -u)
		if [ ! -e "$JOBPATH" ]; then
			JOBS[job$job_index,path$path_index,error]="true"
			logthis 0 "[job $job_index] (not exist) ERROR: The file or folder \"$JOBPATH\" does not exist - this job will not run"
		else
			JOBS[job$job_index,path$path_index,error]="false"

			NUMBEROFIGNORES=$(echo $JSONCONFIGSTRING | jshon -QC -e "jobs" -e $job_index -e "ignores" -l)
			JOBS[job$job_index,path$path_index,ignorelength]=$NUMBEROFIGNORES
			for (( ignore_index=0; ignore_index<$NUMBEROFIGNORES; ignore_index++ )); do
				IGNORESTRING=$(echo $JSONCONFIGSTRING | jshon -QC -e "jobs" -e $job_index -e "ignores" -e $ignore_index -u)
				JOBS[job$job_index,path$path_index,ignore$ignore_index]=$IGNORESTRING
			done

			[ -d "$JOBPATH" ] && JOBS[job$job_index,path$path_index,type]="directory"
			[ -f "$JOBPATH" ] && JOBS[job$job_index,path$path_index,type]="file"
			JOBS[job$job_index,path$path_index,path]=$JOBPATH
			JOBS[job$job_index,command]=$(echo $JSONCONFIGSTRING | jshon -QC -e "jobs" -e $job_index -e "command" -u)
			JOBS[job$job_index,limit]=$(echo $JSONCONFIGSTRING | jshon -QC -e "jobs" -e $job_index -e "limit" -u)
			[ ${JOBS[job$job_index,limit]} = "null" ] && JOBS[job$job_index,limit]=10
		fi
	done

done
logthis 0 "evaluation of config json complete"

# Itterate through valid JOBS to count them and for display / logging, also push valid job paths into FILEPATHS array for inotifywait later on 
jobcount=0
FILEPATHS=()
for (( job_index=0; job_index<$NUMBEROFJOBS; job_index++ )); do
	for (( path_index=0; path_index<${JOBS[job$job_index,pathlength]}; path_index++ )); do
		if [ "${JOBS[job$job_index,path$path_index,error]}" = "false" ]; then
			thistype=${JOBS[job$job_index,path$path_index,type]}
			thispath=${JOBS[job$job_index,path$path_index,path]}
			thiscommand=${JOBS[job$job_index,command]}
			thislimit=${JOBS[job$job_index,limit]}
			
			#compile ignores subkeyarray into readable string
			IGNORES=""
			for (( ignore_index=0; ignore_index<${JOBS[job$job_index,path$path_index,ignorelength]}; ignore_index++ )); do
				IGNORES+="\"${JOBS[job$job_index,path$path_index,ignore$ignore_index]}\" "
			done

			if [ ${JOBS[job$job_index,path$path_index,ignorelength]} = 0 ]; then
				logthis 0 "[job $job_index] ($thistype) Will run \"$thiscommand\" when the $thistype \"$thispath\" changes, limited to $thislimit calls per second"
			else 
				logthis 0 "[job $job_index] ($thistype) Will run \"$thiscommand\" when the $thistype \"$thispath\" changes, limited to $thislimit calls per second (but ignores all file paths that contain ${IGNORES[@]})"
			fi

			let "jobcount++"
			FILEPATHS+=($thispath)
		fi
	done
done

# Start up inotifywait
declare -A TIMESTAMPS
logthis 0 "Starting inotifywait with $jobcount jobs"
inotifywait -mrq -e "modify,attrib,close_write,move,create,delete" --format "%w%f" "${FILEPATHS[@]}" | while read INOTIFYFILE; do
	logthis 1 ""
	logthis 1 ">>> INOTIFYFILE: $INOTIFYFILE"
	for (( job_index=0; job_index<$NUMBEROFJOBS; job_index++ )); do
		for (( path_index=0; path_index<${JOBS[job$job_index,pathlength]}; path_index++ )); do
			if [ "${JOBS[job$job_index,path$path_index,error]}" = "false" ]; then
				thistype=${JOBS[job$job_index,path$path_index,type]}
				thispath=${JOBS[job$job_index,path$path_index,path]}
				thiscommand=${JOBS[job$job_index,command]}
				thislimit=${JOBS[job$job_index,limit]}

				# check ignores match filepath
				ignorematchfound="false"
				for (( ignore_index=0; ignore_index<${JOBS[job$job_index,path$path_index,ignorelength]}; ignore_index++ )); do
					thisignore=${JOBS[job$job_index,path$path_index,ignore$ignore_index]}
					[ "$thisignore" != "" ] && [[ "$INOTIFYFILE" = *"$thisignore"* ]] && ignorematchfound="true"
				done

				if [ "$ignorematchfound" = "true" ]; then
					logthis 1 "[job $job_index] ignoring due to ignore filter"
				else

					[ "$thistype" = "file" ] && CHECKPATH=$INOTIFYFILE
					[ "$thistype" = "directory" ] && CHECKPATH=$(dirname $INOTIFYFILE)
					if [[ "$CHECKPATH" != "$thispath"* ]]; then
						logthis 1 "[job $job_index] no action taken (the file changed does not match the job)"
					else
						# Rate limit check
						limitbroken="false"
						for timestamp in "${!TIMESTAMPS[@]}"; do
							now="$(date '+%s')"
							age=$((now-timestamp))
							historicalcommand=${TIMESTAMPS[$timestamp]}
							[ "$age" -gt "$thislimit" ] && unset $TIMESTAMPS[$timestamp]
							[ "$age" -le "$thislimit" ] && [ "$historicalcommand" = "$thiscommand" ] && limitbroken="true"
						done

						if [ "$limitbroken" = "true" ]; then
							logthis 0 "[job $job_index] change detected in \"$INOTIFYFILE\" which matches the paths (\"$thispath\"), \"$thiscommand\" was already run within $thislimit seconds - not running command again"
						else
							logthis 0 "[job $job_index] change detected in \"$INOTIFYFILE\" which matches the paths (\"$thispath\"), running command:"
							logthis 0 "$thiscommand"
							TIMESTAMPS["$(date '+%s')"]="$thiscommand"
							eval "$thiscommand" | tee -a $log_file
						fi

					fi
					
				fi
			fi
		done
	done
done
