#!/usr/bin/env bash
# Delete orphaned WebP images
# URL: https://github.com/zevilz/remove-orphaned-webp
# Author: Alexandr "zEvilz" Emshanov
# License: MIT
# Version: 1.0.0

cdAndCheck()
{
	cd "$1" 2>/dev/null
	if ! [ "$(pwd)" = "$1" ]; then
		echo
		$SETCOLOR_FAILURE
		if [ -z "$2" ]; then
			echo "Can't get up in a directory $1!" 1>&2
		else
			echo "$2" 1>&2
		fi
		$SETCOLOR_NORMAL
		echo
		exit 1
	fi
}

checkDir()
{
	if ! [ -d "$1" ]; then
		echo
		$SETCOLOR_FAILURE
		if [ -z "$2" ]; then
			echo "Directory $1 not found!" 1>&2
		else
			echo "$2" 1>&2
		fi
		$SETCOLOR_NORMAL
		echo
		exit 1
	fi
}

checkDirPermissions()
{
	cd "$1" 2>/dev/null
	touch checkDirPermissions 2>/dev/null
	if ! [ -f "$1/checkDirPermissions" ]; then
		echo
		$SETCOLOR_FAILURE
		if [ -z "$2" ]; then
			echo "Current user have no permissions to directory $1!" 1>&2
		else
			echo "$2" 1>&2
		fi
		$SETCOLOR_NORMAL
		echo
		exit 1
	else
		rm "$1/checkDirPermissions"
	fi
}

checkParm()
{
	if [ -z "$1" ]; then
		echo
		$SETCOLOR_FAILURE
		echo "$2" 1>&2
		$SETCOLOR_NORMAL
		echo
		exit 1
	fi
}

readableSize()
{
	if [ $1 -ge 1000000000 ]; then
		echo -n $(echo "scale=1; $1/1024/1024/1024" | bc | sed 's/^\./0./')"Gb"
	elif [ $1 -ge 1000000 ]; then
		echo -n $(echo "scale=1; $1/1024/1024" | bc | sed 's/^\./0./')"Mb"
	else
		echo -n $(echo "scale=1; $1/1024" | bc | sed 's/^\./0./')"Kb"
	fi
}

readableTime()
{
	local T=$1
	local D=$((T/60/60/24))
	local H=$((T/60/60%24))
	local M=$((T/60%60))
	local S=$((T%60))
	(( $D > 0 )) && printf '%d days ' $D
	(( $H > 0 )) && printf '%d hours ' $H
	(( $M > 0 )) && printf '%d minutes ' $M
	(( $D > 0 || $H > 0 || $M > 0 )) && printf 'and '
	printf '%d seconds\n' $S
}

findExclude()
{
	if ! [ -z "$EXCLUDE_LIST" ]; then
		EXCLUDE_LIST=$(echo $EXCLUDE_LIST | sed 's/,$//g' | sed 's/^,//g' | sed 's/,/\\|/g')
		grep -v "$EXCLUDE_LIST"
	else
		grep -v ">>>>>>>>>>>>>"
	fi
}

usage()
{
	echo
	echo "Usage: bash $0 [options]"
	echo
	echo "Delete orphaned WebP images."
	echo
	echo "Options:"
	echo
	echo "    -h, --help              Shows this help."
	echo
	echo "    -p <dir>,               Specify full path to input directory with "
	echo "    --path=<dir>            or without slash in the end of path."
	echo
	echo "    -e <list>,              Comma separated parts list of paths to files "
	echo "    --exclude=<list>        for exclusion from search. The script removes "
	echo "                            from the search files in the full path of which "
	echo "                            includes any value from the list."
	echo
}

# Define default script vars
HELP=0
EXCLUDE_LIST=""
PARAMS_NUM=$#
CUR_DIR=$(pwd)
SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"

# Define CRON and direct using styling
if [ "Z$(ps o comm="" -p $(ps o ppid="" -p $$))" == "Zcron" -o \
     "Z$(ps o comm="" -p $(ps o ppid="" -p $(ps o ppid="" -p $$)))" == "Zcron" ]; then
	SETCOLOR_SUCCESS=
	SETCOLOR_FAILURE=
	SETCOLOR_NORMAL=
	BOLD_TEXT=
	NORMAL_TEXT=
else
	SETCOLOR_SUCCESS="echo -en \\033[1;32m"
	SETCOLOR_FAILURE="echo -en \\033[1;31m"
	SETCOLOR_NORMAL="echo -en \\033[0;39m"
	BOLD_TEXT=$(tput bold)
	NORMAL_TEXT=$(tput sgr0)
fi

# Parse options
while [ 1 ] ; do
	if [ "${1#--path=}" != "$1" ] ; then
		DIR_PATH="${1#--path=}"
	elif [ "$1" = "-p" ] ; then
		shift ; DIR_PATH="$1"

	elif [ "${1#--exclude=}" != "$1" ] ; then
		EXCLUDE_LIST="${1#--exclude=}"
	elif [ "$1" = "-e" ] ; then
		shift ; EXCLUDE_LIST="$1"

	elif [[ "$1" = "--help" || "$1" = "-h" ]] ; then
		HELP=1

	elif [[ "$1" = "--quiet" || "$1" = "-q" ]] ; then
		NO_ASK=1

	elif [ -z "$1" ] ; then
		break
	else
		echo
		$SETCOLOR_FAILURE
		echo "Unknown key detected!" 1>&2
		$SETCOLOR_NORMAL
		usage
		exit 1
	fi
	shift
done

# Show help
if [[ $HELP -eq 1 || $PARAMS_NUM -eq 0 ]]; then
	usage
	exit 0
fi

DIR_PATH=$(echo "$DIR_PATH" | sed 's/\/$//')
checkParm "$DIR_PATH" "Path to files not set in -p(--path) option!"
checkDir "$DIR_PATH"
cdAndCheck "$DIR_PATH"
checkDirPermissions "$DIR_PATH"

# Return to script dir to prevent find errors
cd "$SCRIPT_PATH"

# Find images
IMAGES=$(find "$DIR_PATH" -name '*.webp' -or -name '*.WEBP' | findExclude)

# Num of images
IMAGES_TOTAL=$(echo "$IMAGES" | wc -l)

# Preoptimize vars
IMAGES_REMOVED=0
IMAGES_CURRENT=0
START_TIME=$(date +%s)

# If images found
if ! [ -z "$IMAGES" ]; then

	echo "Removing..."

	# Init stat vars
	SAVED_SIZE=0

	# Main optimize loop
	echo "$IMAGES" | ( \
		while read IMAGE ; do

			IMAGES_CURRENT=$(echo "$IMAGES_CURRENT+1" | bc)
			echo -n "["
			echo -n $IMAGES_CURRENT
			echo -n "/"
			echo -n $IMAGES_TOTAL
			echo -n "] "
			echo -n "$IMAGE"
			echo -n '... '

			# Get original image path and extension
			ORIGINAL_IMAGE="${IMAGE%.*}"
			ORIGINAL_IMAGE_EXT="${ORIGINAL_IMAGE##*.}"

			if [[ \
				$ORIGINAL_IMAGE_EXT == "jpg" || \
				$ORIGINAL_IMAGE_EXT == "jpeg" || \
				$ORIGINAL_IMAGE_EXT == "JPG" || \
				$ORIGINAL_IMAGE_EXT == "JPEG" || \
				$ORIGINAL_IMAGE_EXT == "png" || \
				$ORIGINAL_IMAGE_EXT == "PNG" || \
				$ORIGINAL_IMAGE_EXT == "gif" || \
				$ORIGINAL_IMAGE_EXT == "GIF" || \
				$ORIGINAL_IMAGE_EXT == "tiff" || \
				$ORIGINAL_IMAGE_EXT == "TIFF" || \
				$ORIGINAL_IMAGE_EXT == "tif" || \
				$ORIGINAL_IMAGE_EXT == "TIF" \
			]]; then

				if ! [ -f "$ORIGINAL_IMAGE" ]; then

					# Get WebP image size
					IMAGE_SIZE=$(wc -c "$IMAGE" | awk '{print $1}')

					rm "$IMAGE" 2>/dev/null

					if ! [ -f "$IMAGE" ]; then

						SAVED_SIZE=$(echo "$SAVED_SIZE+$IMAGE_SIZE" | bc)
						IMAGES_REMOVED=$(echo "$IMAGES_REMOVED+1" | bc)

						$SETCOLOR_SUCCESS
						echo "[REMOVED]"
						$SETCOLOR_NORMAL

					else

						$SETCOLOR_FAILURE
						echo "[REMOVE FAILED]"
						$SETCOLOR_NORMAL

					fi

				else

					echo "[SKIPPED]"

				fi

			else

				echo "[SKIPPED]"

			fi

		done

		# Total info
		echo
		echo -n "You save: "
		readableSize $SAVED_SIZE
		echo

		echo -n "Removed/Total: "
		echo -n $IMAGES_REMOVED
		echo -n " / "
		echo -n $IMAGES_TOTAL
		echo " files"

		END_TIME=$(date +%s)
		TOTAL_TIME=$(echo "$END_TIME-$START_TIME" | bc)
		echo -n "Total time: "
		readableTime $TOTAL_TIME

	)

else

	echo "No input WebP images found."

fi

echo

cd "$CUR_DIR"

exit 0
