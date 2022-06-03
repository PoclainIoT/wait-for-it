#!/usr/bin/env bash
# Use this script to test if a given TCP host/port are available

# WAITFORIT_cmdname = wait-for-it.sh
WAITFORIT_cmdname=${0##*/}

# If user used the option --quiet, don't print message
# Else, print message received as parameter to stderr
echoerr() { if [[ $WAITFORIT_QUIET -ne 1 ]]; then echo "$@" 1>&2; fi }

# Print usage info to stderr and then exit failure
usage()
{
    cat << USAGE >&2
Usage:
    $WAITFORIT_cmdname host:port [-s] [-t timeout] [-- command args]
    -h HOST | --host=HOST       Host or IP under test
    -p PORT | --port=PORT       TCP port under test
                                Alternatively, you specify the host and port as host:port
    -s | --strict               Only execute subcommand if the test succeeds
    -q | --quiet                Don't output any status messages
    -t TIMEOUT | --timeout=TIMEOUT
                                Timeout in seconds, zero for no timeout
    -- COMMAND ARGS             Execute command with args after the test finishes
USAGE
    exit 1
}

# Handles the connection test and stores its result
wait_for()
{
    # Print message about how long we will wait for the host depending on if a timeout was set or not
    if [[ $WAITFORIT_TIMEOUT -gt 0 ]]; then # User specified a timeout or default timeout is used
        echoerr "$WAITFORIT_cmdname: waiting $WAITFORIT_TIMEOUT seconds for $WAITFORIT_HOST:$WAITFORIT_PORT"
    else # User specified a timeout of 0 so timeout is disabled
        echoerr "$WAITFORIT_cmdname: waiting for $WAITFORIT_HOST:$WAITFORIT_PORT without a timeout"
    fi
    WAITFORIT_start_ts=$(date +%s) # Remember at what time in seconds we started trying to connect to host 
    while :
    do # Try to connect to specified host:port and store exit status (0 if the connection was successful)
       # Two different commands are used to connect depending on the type of timeout (Busybox or not)
        if [[ $WAITFORIT_ISBUSY -eq 1 ]]; then
            nc -z $WAITFORIT_HOST $WAITFORIT_PORT # Command for Busybox timeout
            WAITFORIT_result=$?
        else
            # stdin and stderr output are redirected to /dev/null (void)
            (echo -n > /dev/tcp/$WAITFORIT_HOST/$WAITFORIT_PORT) >/dev/null 2>&1 # Command for regular timeout
            WAITFORIT_result=$?
        fi
        # If the connection was a success, compute the time it took to connect, display a message and break the loop
        if [[ $WAITFORIT_result -eq 0 ]]; then
            WAITFORIT_end_ts=$(date +%s)
            echoerr "$WAITFORIT_cmdname: $WAITFORIT_HOST:$WAITFORIT_PORT is available after $((WAITFORIT_end_ts - WAITFORIT_start_ts)) seconds"
            break
        fi
        sleep 1 # Means that we go through a new iteration of the loop every second
    done
    return $WAITFORIT_result
}

# Handles the timeout and potential interruptions by CTRL+C
# Read http://unix.stackexchange.com/a/57692 for explanations on supporting SIGINT during timeout 
wait_for_wrapper()
{   
    # Call the wait-for-it script again with the same arguments (if original call was made with the quiet option, pass
    # this option on to recursive call), but through the timeout command, which kills the script if it is still running 
    # after the specified amount of time. Child option is added to signify that this is not the original call. 
    if [[ $WAITFORIT_QUIET -eq 1 ]]; then
        timeout $WAITFORIT_BUSYTIMEFLAG $WAITFORIT_TIMEOUT $0 --quiet --child --host=$WAITFORIT_HOST --port=$WAITFORIT_PORT --timeout=$WAITFORIT_TIMEOUT &
    else
        timeout $WAITFORIT_BUSYTIMEFLAG $WAITFORIT_TIMEOUT $0 --child --host=$WAITFORIT_HOST --port=$WAITFORIT_PORT --timeout=$WAITFORIT_TIMEOUT &
    fi
    WAITFORIT_PID=$! # Store the process ID of the timeout command that was just executed in the background
    # If the user presses CTRL+C, the kill command will be executed and stop the timeout process
    trap "kill -INT -$WAITFORIT_PID" INT 
    wait $WAITFORIT_PID
    WAITFORIT_RESULT=$? # After the timeout process is finished (successfully or interrupted), store its exit status
    # If the process failed (because we reached the timeout or because it was interrupted by CTRL+C), print error
    if [[ $WAITFORIT_RESULT -ne 0 ]]; then
        echoerr "$WAITFORIT_cmdname: timeout occurred after waiting $WAITFORIT_TIMEOUT seconds for $WAITFORIT_HOST:$WAITFORIT_PORT"
    fi
    return $WAITFORIT_RESULT
}

# Loop through all the command's arguments and store the information in variables 
while [[ $# -gt 0 ]] # While the number of arguments is > 0
do
    case "$1" in # We look at the first argument
        *:* ) # 1st case -> arg is host:port so we store both their values
        WAITFORIT_hostport=(${1//:/ })
        WAITFORIT_HOST=${WAITFORIT_hostport[0]}
        WAITFORIT_PORT=${WAITFORIT_hostport[1]}
        shift 1 # Shift args to the left so that $1 becomes the next argument
        ;;
        --child) # 2nd case -> arg is --child so we set var WAITFORIT_CHILD to 1
        WAITFORIT_CHILD=1
        shift 1 
        ;;
        -q | --quiet)
        WAITFORIT_QUIET=1
        shift 1
        ;;
        -s | --strict)
        WAITFORIT_STRICT=1
        shift 1
        ;;
        -h) # arg is -h so it should be followed by a host value, which we store in WAITFORIT_HOST
            # if it's not, leave the case statement
        WAITFORIT_HOST="$2"
        if [[ $WAITFORIT_HOST == "" ]]; then break; fi
        shift 2
        ;;
        --host=*) # arg is --host=host so we store the host value in WAITFORIT_HOST
        WAITFORIT_HOST="${1#*=}"
        shift 1
        ;;
        -p)
        WAITFORIT_PORT="$2"
        if [[ $WAITFORIT_PORT == "" ]]; then break; fi
        shift 2
        ;;
        --port=*)
        WAITFORIT_PORT="${1#*=}"
        shift 1
        ;;
        -t)
        WAITFORIT_TIMEOUT="$2"
        if [[ $WAITFORIT_TIMEOUT == "" ]]; then break; fi
        shift 2
        ;;
        --timeout=*)
        WAITFORIT_TIMEOUT="${1#*=}"
        shift 1
        ;;
        --) # arg is -- which means it is followed by a command to be executed after the wait-for-it test finishes
        shift
        WAITFORIT_CLI=("$@") # Store all arguments following the -- to be executed later
        break
        ;;
        --help) # arg is --help so we call usage function to show how wait-for-it is meant to be used
        usage
        ;;
        *) # arg is none of the above, print an error and remind the user the usage of wait-for-it
        echoerr "Unknown argument: $1"
        usage
        ;;
    esac
done

# If during the previous loop, an empty port or host was detected, print an error and remind the usage of wait-for-it
if [[ "$WAITFORIT_HOST" == "" || "$WAITFORIT_PORT" == "" ]]; then
    echoerr "Error: you need to provide a host and port to test."
    usage
fi

# If timeout was not specified, assign default value of 15
WAITFORIT_TIMEOUT=${WAITFORIT_TIMEOUT:-15}
# If strict, child or quiet options were not given in arguments, set values to 0
WAITFORIT_STRICT=${WAITFORIT_STRICT:-0}
WAITFORIT_CHILD=${WAITFORIT_CHILD:-0}
WAITFORIT_QUIET=${WAITFORIT_QUIET:-0}

# Check to see if timeout is from busybox (https://busybox.net/about.html)
WAITFORIT_TIMEOUT_PATH=$(type -p timeout) # Print name of disk file executed by timeout command
# Get absolute filepath from disk filename
# Try two commands in case one is not supported (print errors to /dev/null void)
WAITFORIT_TIMEOUT_PATH=$(realpath $WAITFORIT_TIMEOUT_PATH 2>/dev/null || readlink -f $WAITFORIT_TIMEOUT_PATH)

WAITFORIT_BUSYTIMEFLAG=""
# Check if the filepath has busybox in it
if [[ $WAITFORIT_TIMEOUT_PATH =~ "busybox" ]]; then
    WAITFORIT_ISBUSY=1 # Set Busybox flag to 1
    # Check if Busybox timeout uses -t flag
    # (recent Alpine versions don't support -t anymore)
    if timeout &>/dev/stdout | grep -q -e '-t '; then
        WAITFORIT_BUSYTIMEFLAG="-t"
    fi
else
    WAITFORIT_ISBUSY=0
fi

# If we're inside a recursive call, timeout is already taken care of by original call so we call wait_for directly
if [[ $WAITFORIT_CHILD -gt 0 ]]; then
    wait_for
    WAITFORIT_RESULT=$?
    exit $WAITFORIT_RESULT
else
    # If we're in the original call and timeout is not disabled, we need to call the script again with the timeout 
    # command to make sure it stops trying to connect after a defined period of time, so we call wait_for_wrapper
    if [[ $WAITFORIT_TIMEOUT -gt 0 ]]; then
        wait_for_wrapper
        WAITFORIT_RESULT=$?
    # If timeout was disabled, we can call wait_for directly and it will try connecting until it succeeds
    else
        wait_for
        WAITFORIT_RESULT=$?
    fi
fi

# If we have other commands to execute after the wait-for-it test
if [[ $WAITFORIT_CLI != "" ]]; then
    # If we're in strict mode, commands won't be executed if the test failed so print error and exit 
    if [[ $WAITFORIT_RESULT -ne 0 && $WAITFORIT_STRICT -eq 1 ]]; then
        echoerr "$WAITFORIT_cmdname: strict mode, refusing to execute subprocess"
        exit $WAITFORIT_RESULT
    fi
    # If we're not in strict mode or if the test passed, execute the given commands 
    exec "${WAITFORIT_CLI[@]}"
else # If there are no other commands to execute, exit
    exit $WAITFORIT_RESULT
fi
