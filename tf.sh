#!/bin/bash
# provides built-in functions, aliases, environment variables, etc. that are useful for 
# working with terraform in this environment.

# inputs:  
# TF_ROOT = directory that the scicomp-aws-infrastructure git repo is cloned into, assumes folder structure from there
# TF_SCRIPT_ROOT = directory that has scripts
# TF_ACCOUNT_ROOT = directory that has accounts listed in it 

# default value for parallelism.  Too high and we might hit AWS limits, but too low and it'll take forever
TF_DEFAULT_PARALLELISM=50

# figure out where this script is running from and assume that it's within this git repo.
# if it isn't, then TF_ROOT had better be set prior to sourcing this script
SOURCE="${BASH_SOURCE[0]}"
DIR="$( cd -P "$( dirname "$SOURCE" )" && pwd )"
# assuming this is in the scripts directory, strip the end off one more time
SCRIPT_ROOT=$(dirname "$DIR")

# note: this will give us only the created, modified, destroyed resource: grep -i '^[[:blank:]]*# [^ ]*'

# root of git repo, everything is assumed to be relative to this unless explicitly set otherwise
export TF_ROOT=${TF_ROOT:-$SCRIPT_ROOT}

# scripts are located here
export TF_SCRIPT_ROOT=${TF_SCRIPT_ROOT:-$TF_ROOT/scripts}

# accounts are here, should have two subdirectories
export TF_ACCOUNT_ROOT=${TF_ACCOUNT_ROOT:-$TF_ROOT/accounts}

export TF_DOCS_ROOT=${TF_DOCS_ROOT:-$TF_ROOT/docs}

# use whatever we want for parallelism
export TF_PARALLELISM=${TF_PARALLELISM:-$TF_DEFAULT_PARALLELISM}

export TF_OLDPATH=$PATH

export TF_CUR_PROJECT=${TF_CUR_PROJECT:-test}

export PIPENV_PIPFILE=$TF_SCRIPT_ROOT/Pipfile

# pushd/popd output annoys me, so we'll use these functions
# instead to suppress the output without messing with 
# other scripts that may care about pushd/popd output
# and handle cases where a user may have aliased these commands
function tfpushd() {
    command pushd "$@" > /dev/null
}

function tfpopd() {
    command popd "$@" > /dev/null
}


# set any useful aliases unless told not to
if [ -z $NO_ALIAS ]; then
    echo "I set some aliases"
fi

if [ -z $TF_NO_PATH ]; then
    
    if [ -z $TFRC ] ; then 
        echo "adding terraform scripts to path"
        export PATH=$TF_SCRIPT_ROOT:$PATH
    fi
    
fi

function tfroles() {
    local TF_ENV=$TF_CUR_PROJECT
    local TF_ROLES="all"
    local jqcmd="jq"
    # --environment | -e <environment or all>, defaults to current environment
    # security, admin, billing, all (defaults to all)
    while [ "$1" != "" ]; do
        case $1 in 
            --environment | -e )
                shift
                TF_ENV=$1
                ;;
            security|admin|billing)
                # jq is really bad at using environment variables
                TF_ROLES=".$1"
                jqcmd="$jqcmd $TF_ROLES"
                ;;
            * )
                echo "unknown parameter $1"
                return 1
                ;;
        esac
        shift
    done

    echo "environment is $TF_ENV"
    echo "will output roles for $TF_ROLES"

    if [ "$TF_ENV" == "all" ]; then
        echo "all environments"
    else
        tfpushd $TF_ACCOUNT_ROOT/hdc-$TF_ENV-aws/core
        terraform output -json role_urls | $jqcmd
        local tfresult=$?
        tfpopd
        return $tfresult
    fi
    return 1
}    

# delegated master account- look up
# AWS config- can be for organization but not in master account?  Would be nice to see console in Security account instead
# aws service catalog for globus?  


# echo "Parallelism is set to $TF_PARALLELISM"

# TODO: this will give autocomplete for outputs if used with the right stuff
# tf output | egrep '^(\S*) =' |     -d ' ' -f1

function tf() {
    local TFPARALLEL=""
    if [ -z $NO_PARALLELISM ]; then
        TFPARALLEL="-parallelism=$TF_PARALLELISM"
    else
        echo "Parallelism not set; will use terraform's default value"
    fi
    
    case "$1" in
        plan)
            shift
            terraform plan $TFPARALLEL $@
            return $?;;
        apply)
            shift
            terraform apply $TFPARALLEL $@
            return $?;;
        wo) 
            shift
            tfworkon $@
            return $?;;
        make-account|ma)
            shift
            tfpushd $TF_ACCOUNT_ROOT/hdc-$TF_CUR_PROJECT-aws/core
            pipenv run python $TF_SCRIPT_ROOT/makeaccounts.py $@
            tfpopd
            return $?;;
        ls)
            # TODO: this needs to be python script.  Too complicated for bash to be worth it
            shift
            _tfls
            return $?;;
        create)
            shift
            pipenv run python $TF_SCRIPT_ROOT/createinputs.py $@
            return $?;;
        roles)
            shift
            tfroles $@
            return $?;;
        creds)
            shift
            tfpushd $TF_ACCOUNT_ROOT/hdc-$TF_CUR_PROJECT-aws/accounts
            pipenv run python $TF_SCRIPT_ROOT/sendcredentials.py $@
            local tempret=$?
            tfpopd
            return $tempret;;
        report)
            shift
            tfpushd $TF_ACCOUNT_ROOT/hdc-$TF_CUR_PROJECT-aws/accounts
            pipenv run python $TF_SCRIPT_ROOT/user_reports.py $@
            local tempret=$?
            tfpopd
            return $tempret;;
        admin)
            tfpushd $TF_ACCOUNT_ROOT/hdc-$TF_CUR_PROJECT-aws/core
            tfoj role_urls | jq -r '.admin | to_entries | map([.key, .value[0]]|join(",")) | .[]' | column -s',' -t
            tfpopd
            return 0;;
        test)
            shift
            tfpushd $TF_ROOT/tests
            PIPENV_PIPFILE=$TF_ROOT/tests/Pipfile pipenv run py.test main.py $@
            local tempret=$?
            tfpopd
            return $tempret;;
        *)
            terraform $@
            return $?;;
    esac

}

function tfmakeprofile {
    # creates a CLI profile using the correct role for an account based on the role-chaining in use
    # usage: tfmakerole accountId profile_name
    if [ $# -ne 2 ]; then
        echo "tfmakeprofile requires at least two arguments, the accountId and the profile name."
        echo "tfmakeprofile will create a CLI profile alias for a specified account with the profile name passed to this command."
        echo "It will use the base profile for whatever environment you are currently working on e.g. test, prod, sandbox"
        echo "usage: tfmakeprofile accountId profilename"
        echo "Example:  tfmakeprofile 1111100000 some_account"
        return 1
    fi

    if [ -z $TF_CUR_PROJECT ]; then
        echo "TF_CUR_PROJECT is not set or empty.  Please select an environment using tfworkon <environment name> and try again."
        return 1
    fi
    local act=$1
    local create_profile=$2

    echo "Creating profile $create_profile for account $act in $TF_CUR_PROJECT environment."
    
    cmd="aws configure --profile $create_profile set source_profile $TF_CUR_PROJECT-terraform-master"
    echo "running $cmd"
    $cmd

    cmd="aws configure --profile $create_profile set role_arn arn:aws:iam::$act:role/OrganizationAccountAccessRole"
    echo "running $cmd"
    $cmd

    cmd="aws configure --profile $create_profile set region us-west-2"
    echo "running $cmd"
    $cmd

    cmd="aws configure --profile $create_profile set session_name terraform"
    echo "running $cmd"
    $cmd

    cmd="aws configure --profile $create_profile set s3.max_concurrent_requests 100"
    echo "running $cmd"
    $cmd

    cmd="aws configure --profile $create_profile set s3.max_queue_size 10000"
    echo "running $cmd"
    $cmd

    cmd="aws configure --profile $create_profile set s3.multipart_chunksize 16MB"
    echo "running $cmd"
    $cmd
    
# s3 =
#        max_concurrent_requests = 100
#        max_queue_size = 10000
#        multipart_threshold = 64MB
#        multipart_chunksize = 16MB

    return 0
}

function tfcreateinputs {
    # TODO: support direct download from Toolbox for json files needed.
    # NOTE: will run from a folder data_toolbox that is adjacent to the git repo for terraform
    tf create --outdir $TF_ACCOUNT_ROOT/hdc-prod-aws/core --pifile $TF_ROOT/../data_toolbox/pi.json --usersfile $TF_ROOT/../data_toolbox/users.json "$@"
}

# get some info about the environment that this is running in
function tfenv() {
    echo "Root directory of repo TF_ROOT: $TF_ROOT"
    echo "Scripts TF_SCRIPT_ROOT: $TF_SCRIPT_ROOT"
    echo "Accuounts TF_ACCOUNT_ROOT: $TF_ACCOUNT_ROOT"
    echo "Docs is TF_DOCS_ROOT: $TF_DOCS_ROOT" 
    echo "Parallelism is set to TF_PARALLELISM: $TF_PARALLELISM"
    echo "Current project is TF_CUR_PROJECT: $TF_CUR_PROJECT"

}

function _tfgetacts() {
    tfpushd $TF_ACCOUNT_ROOT
    # for d in ls; do
    tfpopd
}

function tfworkon() {
    if [ $# -eq 0 ]; then
        echo "no args passed"
        echo "Please select an environment from the list:"
        _tfls
        return 1
    else
        local tfdir=hdc-$1-aws
        if [ -d $TF_ACCOUNT_ROOT/$tfdir ]; then
            cd $TF_ACCOUNT_ROOT/$tfdir/core
            TF_CUR_PROJECT=$1
            return $?
        else
            echo "$tfdir does not exist."
            echo "Please select an environment from the list:"
            _tfls
            return 1
        fi
    fi
}

function _tfls() {
    tfpushd $TF_ACCOUNT_ROOT
    ls | cut -d '-' -f2
    tfpopd
}

function tfo() {
    if [ "$1" == "ls" ]; then
        tfoj | jq 'keys'
        return $?
    else
        terraform output $@
        return $?
    fi
}

function tfoj() {
    terraform output -json $@
    return $?
}

function tfp() {
    tf "plan" "$@"
    return $?
}

# run tf plan but log only resource names being modified to ./plan.txt
function tfpl() {
    tf "plan" -no-color "$@" | tee >(grep -i '^[[:blank:]]*# [^ ]*' | cut -d' ' -f4 >plan.txt)
}

# run tf plan but log resource names 
function tfps() {
    tf "plan" -no-color "$@" | tee >(grep -i '^[[:blank:]]*# [^ ]*' | cut -d'#' -f2 >plansummary.txt)
}

function tfa() {
    tf "apply" "$@"
    return $?
}

function createmodule() {
    $TF_SCRIPT_ROOT/createmodule.sh "$@"
}

function tfexit() {
    export PATH=$TF_OLDPATH
    unset TFRC
    unset PIPENV_PIPFILE
    unset -f createmodule
    unset -f tfo
    unset -f tfp
    unset -f tfa
    unset -f tf
    unset -f tfenv
    unset -f _tfls
    unset -f tfworkon
    unset -f tfpushd
    unset -f tfpopd
    unset -f tfcreateinputs
    unset -f tfroles
    unset -f tfoj
}

export TFRC=1

# s3 =
#        max_concurrent_requests = 100
#        max_queue_size = 10000
#        multipart_threshold = 64MB
#        multipart_chunksize = 16MB