#! /bin/sh

SCRIPTPATH="$0"
while [ -h "$SCRIPTPATH" ]; do
	SCRIPTDIR="$(cd -P "$(dirname "$SCRIPTPATH")" >/dev/null && pwd)"
	SCRIPTPATH="$(readlink "$SCRIPTPATH")"
	[[ $SCRIPTPATH != /* ]] && SOURCE="$SCRIPTDIR/$SCRIPTPATH"
done
SCRIPTPATH="$(cd -P "$(dirname "$SCRIPTPATH")" >/dev/null && pwd)"

# Check for required files

if [[ ! -f "$SCRIPTPATH/sources" ]]; then
	>&2 echo "spotscript: could not find sources-file in working directory"
	exit 1
fi

# Source directories
source "$SCRIPTPATH/sources"

# Players
VIDEOPLAYER="mpv"
SYNCPLAY="syncplay --no-gui"

# Messages
USAGE="usage: play [-h|-l|-rs|-S<season number> [-E<episode number>]] PATTERN"
INV_ARG="play: invalid argument --"
NO_SEL="play: no selection"

# Menu
ROFI="rofi -dmenu -i -p play"

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

# Input arguments
PATTERN=$@

# Set array delimiter
IFS=$'\n'

# Fetch media index
for tvdir in ${TVSHOWS[@]}; do
	TVDIRS+=$(find -L "$HOME$tvdir" -maxdepth 1 -type d | grep -v "\$RECYCLE.BIN")
	TVDIRS+=$'\n'
done

TVDIRS=$(echo "$TVDIRS" | awk '{FS="/" ; $0=$0 ; print $NF"|"$0}' | sort -t/ -k1 | cut -d"|" -f2 | grep -v '^$')

for moviedir in ${MOVIES[@]}; do
	MOVIEDIRS+=$(find -L "$HOME$moviedir" -maxdepth 1 -type d | grep -v "\$RECYCLE.BIN")
	MOVIEDIRS+=$'\n'
done

MOVIEDIRS=$(echo "$MOVIEDIRS" | awk '{FS="/" ; $0=$0 ; print $NF"|"$0}' | sort -t/ -k1 | cut -d"|" -f2 | grep -v '^$')

# Basic filter
if [[ $PATTERN ]]; then
	TVDIRS=$(echo "$TVDIRS" | grep -i "$PATTERN")
	MOVIEDIRS=$(echo "$MOVIEDIRS" | grep -i "$PATTERN")
fi

# List initial matches and exit
if [[ $LIST && $PATTERN ]]; then
	echo #
	if [[ $TVDIRS ]]; then
		echo -e "TV Shows\n------\n$TVDIRS\n"
	fi
	if [[ $MOVIEDIRS ]]; then
		echo -e "Movies\n------\n$MOVIEDIRS\n"
	fi
	exit
fi

# First refined selection step
if [[ $TVDIRS && $MOVIEDIRS ]]; then
	OPTIONS=("Movie" "TV Show")
	REPLY=$(eval "echo \"${OPTIONS[*]}\" | $ROFI")

	if [[ $REPLY = "Movie" ]]; then
		DIRS="$MOVIEDIRS"
		TITLES=$(basename -a $(echo "$DIRS"))
		TYPE="Movie"
	elif [[ $REPLY = "TV Show" ]]; then
		DIRS="$TVDIRS"
		TITLES=$(basename -a $(echo "$DIRS"))
		TYPE="TV Show"
	else
		>&2 echo "$NO_SEL"
		exit 1
	fi

elif [[ $TVDIRS ]]; then
	DIRS="$TVDIRS"
	TITLES=$(basename -a $(echo "$DIRS"))
	TYPE="TV Show";
elif [[ $MOVIEDIRS ]]; then
	DIRS="$MOVIEDIRS"
	TITLES=$(basename -a $(echo "$DIRS"))
	TYPE="Movie"
fi

NUM_TITLES=$(echo -e "$TITLES" | grep -c '^')

# Second refined selection step
if [[ $NUM_TITLES -gt 1 ]]; then
	REPLY=$(eval "echo \"$TITLES\" | $ROFI")

	if [[ $REPLY ]]; then
		DIRS=$(echo "$DIRS" | grep "$REPLY")
		TITLES=$(echo "$TITLES" | grep "$REPLY")
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
		MATCHES=$(echo "$MATCHES" | grep "$REPLY")
	else
		>&2 echo "$NO_SEL"
		exit 1
	fi

fi

# Final selection step for TYPE:TV Show and general print to TARGET
if [[ $TYPE = "Movie" ]]; then
	TARGET="$MATCHES"
elif [[ $SHUF && $TYPE = "TV Show" ]]; then

	if [[ $SEL_S ]]; then
		MATCHES=$(echo "$MATCHES" | grep "Season $SEL_S")
	fi

	TARGET=$(echo "$MATCHES" | shuf -n 1)
elif [[ $TYPE = "TV Show" ]]; then

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

		MATCHES=$(echo "$MATCHES" | grep "Season $SEL_S")
	elif [[ $SEL_S ]]; then
		MATCHES=$(echo "$MATCHES" | grep "Season $SEL_S")
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

		TARGET=$(echo "$MATCHES" | grep "$REPLY")
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
