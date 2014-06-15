#!/bin/sh

##########
# CONFIG #
##########
HOME=~/.chromecastize
SUPPORTED_EXTENSIONS=('mkv' 'avi' 'mp4' '3gp' 'mov' 'mpg' 'mpeg' 'qt' 'wmv' 'm2ts')

SUPPORTED_GFORMATS=('MPEG-4' 'Matroska')
UNSUPPORTED_GFORMATS=('BDAV' 'AVI')

SUPPORTED_VCODECS=('AVC')
UNSUPPORTED_VCODECS=('MPEG-4 Visual')

SUPPORTED_ACODECS=('AAC' 'MPEG Audio')
UNSUPPORTED_ACODECS=('AC-3')

DEFAULT_VCODEC=h264
DEFAULT_ACODEC=libvorbis
DEFAULT_GFORMAT=mkv

#############
# FUNCTIONS #
#############

# Check if a value exists in an array
# @param $1 mixed  Needle  
# @param $2 array  Haystack
# @return  Success (0) if value exists, Failure (1) otherwise
# Usage: in_array "$needle" "${haystack[@]}"
# See: http://fvue.nl/wiki/Bash:_Check_if_array_element_exists
in_array() {
    local hay needle=$1
    shift
    for hay; do
        [[ $hay == $needle ]] && return 0
    done
    return 1
}

print_help() {
	echo "Usage: chromecastize.sh <videofile1> [ videofile2 ... ]"
}

unknown_codec() {
	echo "'$1' is an unknown codec. Please add it to the list in a CONFIG section."
}

is_supported_gformat() {
	if in_array "$1" "${SUPPORTED_GFORMATS[@]}"; then
                return 0
        elif in_array "$1" "${UNSUPPORTED_GFORMATS[@]}"; then
                return 1
        else
                unknown_codec "$1"
                exit 1
        fi
}

is_supported_vcodec() {
	if in_array "$1" "${SUPPORTED_VCODECS[@]}"; then
		return 0
	elif in_array "$1" "${UNSUPPORTED_VCODECS[@]}"; then
		return 1
	else
		unknown_codec "$1"
		exit 1
	fi
}

is_supported_acodec() {
	if in_array "$1" "${SUPPORTED_ACODECS[@]}"; then
		return 0
	elif in_array "$1" "${UNSUPPORTED_ACODECS[@]}"; then
		return 1
	else
		unknown_codec "$1"
		exit 1
	fi
}

is_supported_ext() {
	EXT=`echo $1 | tr '[:upper:]' '[:lower:]'`
	in_array "$EXT" "${SUPPORTED_EXTENSIONS[@]}"
}

mark_as_good() {
	# add file as successfully converted
	FILENAME=$1
	echo `grealpath "$FILENAME"` >> $HOME/processed_files
}

on_success() {
	FILENAME="$1"
	mark_as_good "$FILENAME.mkv"
	mv "$FILENAME" "$FILENAME.bak"
}

on_failure() {
	FILENAME="$1"
	rm "$FILENAME"
}

process_file() {
	echo "==========="
        echo "Processing: $FILENAME"

        # test extension
        BASENAME=$(basename "$FILENAME")
        EXTENSION="${BASENAME##*.}"
        if ! is_supported_ext "$EXTENSION"; then
                echo "- not a video format, skipping"
                continue
        fi

	# test if it's an `chromecastize` generated file
	if grep -Fxq "`grealpath "$FILENAME"`" $HOME/processed_files; then
		echo '- file was genereated by `chromecastize`, skipping'
		continue
	fi

	# test general format
        INPUT_GFORMAT=`mediainfo --Inform="General;%Format%\n" "$FILENAME" | head -n1`
        if is_supported_gformat "$INPUT_GFORMAT"; then
                OUTPUT_GFORMAT="ok"
        else
                OUTPUT_GFORMAT="$DEFAULT_GFORMAT"
        fi
        echo "- general: $INPUT_GFORMAT -> $OUTPUT_GFORMAT"

        # test video codec
        INPUT_VCODEC=`mediainfo --Inform="Video;%Format%\n" "$FILENAME" | head -n1`
        if is_supported_vcodec "$INPUT_VCODEC"; then
                OUTPUT_VCODEC="copy"
        else
                OUTPUT_VCODEC="$DEFAULT_VCODEC"
        fi
        echo "- video: $INPUT_VCODEC -> $OUTPUT_VCODEC"

        # test audio codec
        INPUT_ACODEC=`mediainfo --Inform="Audio;%Format%\n" "$FILENAME" | head -n1`
        if is_supported_acodec "$INPUT_ACODEC"; then
                OUTPUT_ACODEC="copy"
        else
                OUTPUT_ACODEC="$DEFAULT_ACODEC"
        fi
        echo "- audio: $INPUT_ACODEC -> $OUTPUT_ACODEC"

        if [ "$OUTPUT_VCODEC" = "copy" ] && [ "$OUTPUT_ACODEC" = "copy" ] && [ "$OUTPUT_GFORMAT" = "ok" ]; then
                echo "- file should be playable by Chromecast!"
		mark_as_good "$FILENAME"
        else
                echo "- video length: `mediainfo --Inform="General;%Duration/String3%" "$FILENAME"`"
                ffmpeg -loglevel panic -stats -i "$FILENAME" -vcodec "$OUTPUT_VCODEC" -acodec "$OUTPUT_ACODEC" "$FILENAME.mkv" && on_success "$FILENAME" || on_failure "$FILENAME"
        fi
}

################
# MAIN PROGRAM #
################

# test if `mediainfo` is available
MEDIAINFO=`which mediainfo`
if [ -z $MEDIAINFO ]; then
	echo '`mediainfo` is not available, please install it'
	exit 1
fi

# test if `ffmpeg` is available
FFMPEG=`which ffmpeg`
if [ -z $FFMPEG ]; then
	echo '`ffmpeg` is not available, please install it'
	exit 1
fi

# test if `grealpath` is available
REALPATH=`which grealpath`
if [ -z $REALPATH ]; then
        echo '`grealpath` is not available, please install it'
        exit 1
fi

# check number of arguments
if [ $# -lt 1 ]; then
	print_help
	exit 1
fi

# ensure that processed_files file exists
mkdir -p $HOME
touch $HOME/processed_files

for FILENAME in "$@"; do
	process_file $FILENAME
done
