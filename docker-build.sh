#!/bin/bash

set -e

source $(dirname $0)/cfg.env
script_name="$0"

function usage() {
    echo "$script_name [--use-current-branch --skip-latest --clean-submodule] version action(build/push) image_name [docker_file_name]"
    exit 1
}

x=""
use_current_branch=0
skip_latest=0
image=""
dockerfile="Dockerfile"
clean_submodule=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --use-current-branch)
            use_current_branch=1
            shift # past argument
            ;;
        --skip-latest)
            skip_latest=1
            shift 
            ;;
        --clean-submodule)
            clean_submodule=1
            shift 
            ;;
        --*)
            echo "Unknown option $1"
            exit 1
            ;;
        *)
            break
            ;;
    esac
done

if [ -z "$1" ]; then
    echo "wrong usage, must provide tag version, e.g. 4,25"
    usage
fi
x="$1"

if [ "$2" != "build" -a "$2" != "push" ]; then
    echo "wrong usage, must provide action(build/push)."
    usage
fi
action="$2"

if [ -z "$3" ]; then
    echo "wrong usage, must provide image name."
    usage
fi
image="$3"
base_image_name=$(basename $image)
if [ "$image_base_name" = "pika" ]; then
    clean_submodule=1
fi

if [ ! -z "$4" ]; then
    dockerfile="$4"
fi

echo "tag: '$x', action: '$action', use_current_branch: $use_current_branch, image: '$image', dockerfile: '$dockerfile'"

if [ "$(git diff HEAD)" != "" ]; then
    echo "plz save your work first"
    exit 1
fi

set -x
if [[ $use_current_branch -eq 0 ]]; then
    set +e
    git checkout -b tmp 
    if [[ $? -ne 0 ]]; then
        git checkout tmp
    fi
    set -e

    git fetch origin
    git reset --hard origin/master
    git reset --hard $x
fi

if [[ $clean_submodule -eq 1 ]]; then
    git submodule foreach --recursive git clean -xfd
    git submodule foreach --recursive git reset --hard
    git submodule update --init --recursive
fi

docker build --no-cache -f $dockerfile -t $base_image_name:$x .
docker tag $base_image_name:$x $image:$x

set +e
if [ "$action" = "push" ]; then
    while true
    do
        docker login --username $username --password $password $harbor_addr
        docker push $image:$x
        if [ $? -eq 0 ]; then
            break
        fi
        sleep 3s
    done
fi
set -e

if [ $skip_latest -eq 1 ]; then
    exit 0
fi

latest="$image:latest"
set +e
ret_msg=$(docker pull "$latest" 2>&1)
if [ $? -ne 0 ]; then
    if [[ $ret_msg == *"manifest for $image:latest not found"* ]]; then
        latest_version=0.0.0
    fi
else
    latest_version=$(docker inspect $latest | grep "${base_image_name}:" | grep -v latest | awk '{print $1}' | sed --expression s/\"//g | sed --expression s/,//g | sed --expression s/"${base_image_name}:"//g | grep -v harbor)
fi
echo "latest version: $latest_version"

#latest_version=0.0.0
if [ -z "$latest_version" ]; then
    echo "latest_version is empty, continue?"
    select yn in "Yes" "No"; do
        case $yn in
            Yes ) break;;
            No  ) exit 1;; 
        esac
    done
else
    ret=$("$(dirname "$0")/version-compare" "$x" "$latest_version")

    if [ $? -ne 0 ]; then
        echo "version compare failed"
        exit 1
    fi

    if [ ! $ret -gt 0 ]; then
        echo "version must be greater than latest version $latest_version"
        exit 1
    fi
fi
set -e

docker tag $base_image_name:$x $latest
docker push $latest

#~/bin/docker-run $image:$x
