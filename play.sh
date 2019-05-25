#! /bin/bash

# Players
VIDEOPLAYER="mpv"
SYNCPLAY="syncplay --no-gui"

# Menu
ROFI="rofi -dmenu -i -p play"

# Find path of script

SCRIPTPATH="$0"
while [ -h "$SCRIPTPATH" ]; do
	SCRIPTDIR="$(cd -P "$(dirname "$SCRIPTPATH")" >/dev/null && pwd)"
	SCRIPTPATH="$(readlink "$SCRIPTPATH")"
	[[ $SCRIPTPATH != /* ]] && SOURCE="$SCRIPTDIR/$SCRIPTPATH"
done
SCRIPTPATH="$(cd -P "$(dirname "$SCRIPTPATH")" >/dev/null && pwd)"

# Check for required files

if [[ ! -f "$SCRIPTPATH/sources" ]]; then
	>&2 echo "play: could not find sources-file in working directory"
	exit 1
fi

# Set array delimiter
IFS=$'\n'

# Source directories
mapfile -t SOURCES < "$SCRIPTPATH/sources"

for source in ${SOURCES[@]}; do
	case $source in
		"[movies]")
			CATEGORY="MOVIES"
			;;
		"[series]")
			CATEGORY="SERIES"
			;;
		"/"*)
			eval "$CATEGORY"+="'$source'$'\n'"
			;;
		"~"*)
			eval "$CATEGORY"+="'${HOME}${source:1}'$'\n'"
			;;
		*)
			>&2 echo "play: sources-file contains invalid lines"
			exit 1
			;;
	esac
done

# Messages
USAGE="usage: play [-h|-l|-rs|-S<season number> [-E<episode number>]] PATTERN"
INV_ARG="play: invalid argument --"
NO_SEL="play: no selection"

# Integer-matching regexp
INTEXP='^[0-9]+([.][0-9]+)?$'

# Input flags
while getopts ":hlrsS:E:" opt; do

	case $opt in
		h)
			echo "$USAGE"
			exit
			;;
		l)
			LIST=1
			;;
		r)
			SHUF=1
			;;
		s)
			SYNC=1
			;;
		S)
			if [[ $OPTARG =~ $INTEXP ]]; then
				SEL_S=$(printf %02d $OPTARG)
			elif [[ $OPTARG ]]; then
				>&2 echo -e "$INV_ARG '$OPTARG'\n$USAGE"
				exit 1
			fi
			;;
		E)
			if [[ $OPTARG =~ $INTEXP && $SEL_S ]]; then
				SEL_EP=$(printf %02d $OPTARG)
			elif [[ ! $SEL_S ]]; then
				>&2 echo -e "play: episode selection requires season selection\n$USAGE"
				exit 1
			elif [[ $OPTARG ]]; then
				>&2 echo -e "$INV_ARG '$OPTARG'\n$USAGE"
				exit 1
			fi
			;;
		\?)
			>&2 echo -e "play: invalid option -- '$OPTARG'\n$USAGE"
			exit 1
			;;
	esac

done

#Shift argument indices
shift $((OPTIND-1))

# Store input pattern
PATTERN="$@"

# Fetch media index
for moviedir in ${MOVIES[@]}; do
	MOVIEDIRS+="$(find -L "$moviedir" -maxdepth 1 -type d | grep -v "\$RECYCLE.BIN")"
done

MOVIEDIRS=$(echo "$MOVIEDIRS" | awk '{FS="/" ; $0=$0 ; print $NF"|"$0}' | sort -t/ -k1 | cut -d"|" -f2 | grep -v '^$')

for seriesdir in ${SERIES[@]}; do
	SERIESDIRS+="$(find -L "$seriesdir" -maxdepth 1 -type d | grep -v "\$RECYCLE.BIN")"
done

SERIESDIRS=$(echo "$SERIESDIRS" | awk '{FS="/" ; $0=$0 ; print $NF"|"$0}' | sort -t/ -k1 | cut -d"|" -f2 | grep -v '^$')

# Basic filter
if [[ $PATTERN ]]; then
	MOVIEDIRS=$(echo "$MOVIEDIRS" | grep -iF "$PATTERN")
	SERIESDIRS=$(echo "$SERIESDIRS" | grep -iF "$PATTERN")
fi

# List initial matches and exit
if [[ $LIST && $PATTERN ]]; then
	if [[ ! $SERIESDIRS && ! $MOVIEDIRS ]]; then
		echo -e "No matches for '$PATTERN'"
		exit
	fi
	echo #
	if [[ $MOVIEDIRS ]]; then
		echo -e "Movies\n------\n$MOVIEDIRS\n"
	fi
	if [[ $SERIESDIRS ]]; then
		echo -e "Series\n------\n$SERIESDIRS\n"
	fi
	exit
elif [[ $LIST ]]; then
	>&2 echo -e "play: list option requires a pattern to match"
	exit 1
fi

# First refined selection step
if [[ $MOVIEDIRS && $SERIESDIRS ]]; then
	OPTIONS=("Movie" "Series")
	REPLY=$(eval "echo \"${OPTIONS[*]}\" | $ROFI")

	if [[ $REPLY = "Movie" ]]; then
		DIRS="$MOVIEDIRS"
		TITLES=$(basename -a $(echo "$DIRS"))
		TYPE="Movie"
	elif [[ $REPLY = "Series" ]]; then
		DIRS="$SERIESDIRS"
		TITLES=$(basename -a $(echo "$DIRS"))
		TYPE="Series"
	else
		>&2 echo "$NO_SEL"
		exit 1
	fi

elif [[ $MOVIEDIRS ]]; then
	DIRS="$MOVIEDIRS"
	TITLES=$(basename -a $(echo "$DIRS"))
	TYPE="Movie"
elif [[ $SERIESDIRS ]]; then
	DIRS="$SERIESDIRS"
	TITLES=$(basename -a $(echo "$DIRS"))
	TYPE="Series";
fi

NUM_TITLES=$(echo -e "$TITLES" | grep -c '^')

# Second refined selection step
if [[ $NUM_TITLES -gt 1 ]]; then
	REPLY=$(eval "echo \"$TITLES\" | $ROFI")

	if [[ $REPLY ]]; then
		DIRS=$(echo "$DIRS" | grep -F "/$REPLY")
		TITLES=$(echo "$TITLES" | grep -F "/$REPLY")
	else
		DIRS=""
		TITLES=""
	fi

fi

if [[ $DIRS ]]; then
	MATCHES=$(find -L "$DIRS" -name "*.mkv*")
	NUM_MATCHES=$(echo -e "$MATCHES" | grep -c '^')
else
	>&2 echo "play: '$PATTERN': no matches"
	exit 1
fi

if [[ ! $MATCHES ]]; then
	>&2 echo "play: '$DIRS': no video file found in directory"
	exit 1
fi


# Final selection step for TYPE:Movie
if [[ $TYPE = "Movie" && $NUM_MATCHES -gt 1 ]]; then

	REPLY=$(basename -a $(eval "echo \"$MATCHES\" | $ROFI"))

	if [[ $REPLY ]]; then
		MATCHES=$(echo "$MATCHES" | grep -F "$REPLY")
	else
		>&2 echo "$NO_SEL"
		exit 1
	fi

fi

# Final selection step for TYPE:Series and general print to TARGET
if [[ $TYPE = "Movie" ]]; then
	TARGET="$MATCHES"
elif [[ $SHUF && $TYPE = "Series" ]]; then

	if [[ $SEL_S ]]; then
		MATCHES=$(echo "$MATCHES" | grep "$SEL_S/")
	fi

	TARGET=$(echo "$MATCHES" | shuf -n 1)
elif [[ $TYPE = "Series" ]]; then

	# Season selection
	for match in $MATCHES; do
		SEASONS+=($(basename $(dirname $match)))
	done

	SEASONS=$(echo "${SEASONS[*]}" | sort -u)
	NUM_SEASONS=$(echo "$SEASONS" | grep -c '^')

	if [[ $NUM_SEASONS -gt 1  && ! $SEL_S ]]; then

		REPLY=$(eval "echo \"$SEASONS\" | $ROFI")

		if [[ $REPLY ]]; then
			SEL_S=$(echo $REPLY | awk 'NF>1{print $NF}')
		else
			>&2 echo "$NO_SEL"
			exit 1
		fi

		MATCHES=$(echo "$MATCHES" | grep "$SEL_S/")
	elif [[ $SEL_S ]]; then
		MATCHES=$(echo "$MATCHES" | grep "$SEL_S/")
	fi

	if [[ ! $MATCHES ]]; then
		>&2 echo "play: folder structure error"
		exit 1
	fi

	# Episode selection
	EPISODES=$(basename -s .mkv $MATCHES | sort)
	NUM_EPISODES=$(echo "$EPISODES" | grep -c '^')

	if [[ $NUM_EPISODES -gt 1 && ! $SEL_EP ]]; then

		REPLY=$(eval "echo \"$EPISODES\" | $ROFI")

		if [[ ! $REPLY ]]; then
			>&2 echo "$NO_SEL"
			exit 1
		fi

		TARGET=$(echo "$MATCHES" | grep -F "$REPLY")
	else
		TARGET=$(echo "$MATCHES" | grep $(echo "$EPISODES" | sed -n "$SEL_EP"p))
	fi

fi

# Execution
if [[ $TARGET && $SYNC ]]; then
	eval "$SYNCPLAY \"$TARGET\""
elif [[ $TARGET ]]; then
	eval "$VIDEOPLAYER \"$TARGET\""
else
	>&2 echo "play: unexpected error"
	exit 1
fi
