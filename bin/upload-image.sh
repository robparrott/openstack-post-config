#!/usr/bin/env bash
# upload_image.sh - Retrieve and upload an image into Glance
#
# upload_image.sh <image-url>
#
# Assumes credentials are set via OS_* environment variables

function usage {
    echo "$0 - Retrieve and upload an image into Glance"
    echo ""
    echo "Usage: $0 <image-url> [...]"
    echo ""
    echo "Assumes credentials are set via OS_* environment variables"
    exit 1
}

# Grab a numbered field from python prettytable output
# Fields are numbered starting with 1
# Reverse syntax is supported: -1 is the last field, -2 is second to last, etc.
# get_field field-number
function get_field() {
    while read data; do
        if [ "$1" -lt 0 ]; then
            field="(\$(NF$1))"
        else
            field="\$$(($1 + 1))"
        fi
        echo "$data" | awk -F'[ \t]*\\|[ \t]*' "{print $field}"
    done
}

function get_image_id 
{
  id=$( glance image-show ${1} | grep "^| id " | awk '{print $4}' )
  echo ${id}
}

# Retrieve an image from a URL and upload into Glance
# Uses the following variables:
#   ``FILES`` must be set to the cache dir
#   ``GLANCE_HOSTPORT``
# upload_image image-url glance-token

function upload_image() {
    local image_url=$1
    local token=$2

    local token_arg=
    if ! [ -z $token ]; then
          token_arg="--os-auth-token $token"
    fi

    # Create a directory for the downloaded image tarballs.
    mkdir -p $FILES/images

    # Determine the image name and options to use
    IMAGE_FNAME=`basename "$image_url"`

    # Downloads the image (uec ami+aki style), then extracts it.
    if [[ ! -f $FILES/$IMAGE_FNAME || "$(stat -c "%s" $FILES/$IMAGE_FNAME)" = "0" ]]; then
        wget -c $image_url -O $FILES/$IMAGE_FNAME
        if [[ $? -ne 0 ]]; then
            echo "Not found: $image_url"
            return
        fi
    fi

    # unbzip anything that has been copmressed
    if [[ ${IMAGE_FNAME} =~ '.bz2' ]]; then
       bunzip2 $FILES/$IMAGE_FNAME 2>/dev/null || /bin/true
       IMAGE_FNAME=$( echo $IMAGE_FNAME | sed 's/\.bz2//' )
    fi 

    # OpenVZ-format images are provided as .tar.gz, but not decompressed prior to loading
    if [[ "$image_url" =~ 'openvz' ]]; then
        IMAGE="$FILES/${IMAGE_FNAME}"
        IMAGE_NAME="${IMAGE_FNAME%.tar.gz}"
        id=$( get_image_id $IMAGE_NAME )
        glance $token_arg \
               --os-image-url http://$GLANCE_HOSTPORT \
               image-create \
               --name "$IMAGE_NAME" \
               --is-public=True \
               --container-format ami \
               --disk-format ami < "${IMAGE}"
        return
    fi

    # XenServer-ovf-format images are provided as .vhd.tgz as well
    # and should not be decompressed prior to loading
    if [[ "$image_url" =~ '.vhd.tgz' ]]; then
        IMAGE="$FILES/${IMAGE_FNAME}"
        IMAGE_NAME="${IMAGE_FNAME%.vhd.tgz}"
        id=$( get_image_id $IMAGE_NAME )
        glance $token_arg \
               --os-image-url http://$GLANCE_HOSTPORT \
               image-create \
               --name "$IMAGE_NAME" \
               --is-public=True \
               --container-format=ovf \
               --disk-format=vhd < "${IMAGE}"
        return
    fi

    KERNEL=""
    RAMDISK=""
    DISK_FORMAT=""
    CONTAINER_FORMAT=""
    UNPACK=""
    case "$IMAGE_FNAME" in
        *.tar.gz|*.tgz)
            # Extract ami and aki files
            [ "${IMAGE_FNAME%.tar.gz}" != "$IMAGE_FNAME" ] &&
                IMAGE_NAME="${IMAGE_FNAME%.tar.gz}" ||
                IMAGE_NAME="${IMAGE_FNAME%.tgz}"
            xdir="$FILES/images/$IMAGE_NAME"
            rm -Rf "$xdir";
            mkdir "$xdir"
            tar -zxf $FILES/$IMAGE_FNAME -C "$xdir"
            KERNEL=$(for f in "$xdir/"*-vmlinuz* "$xdir/"aki-*/image; do
                     [ -f "$f" ] && echo "$f" && break; done; true)
            RAMDISK=$(for f in "$xdir/"*-initrd* "$xdir/"ari-*/image; do
                     [ -f "$f" ] && echo "$f" && break; done; true)
            IMAGE=$(for f in "$xdir/"*.img "$xdir/"ami-*/image; do
                     [ -f "$f" ] && echo "$f" && break; done; true)
            if [[ -z "$IMAGE_NAME" ]]; then
                IMAGE_NAME=$(basename "$IMAGE" ".img")
            fi
            ;;
        *.img)
            IMAGE="$FILES/$IMAGE_FNAME";
            IMAGE_NAME=$(basename "$IMAGE" ".img")
            format=$(qemu-img info ${IMAGE} | awk '/^file format/ { print $3; exit }')
            if [[ ",qcow2,raw,vdi,vmdk,vpc," =~ ",$format," ]]; then
                DISK_FORMAT=$format
            else
                DISK_FORMAT=raw
            fi
            CONTAINER_FORMAT=bare
            ;;
        *.img.gz)
            IMAGE="$FILES/${IMAGE_FNAME}"
            IMAGE_NAME=$(basename "$IMAGE" ".img.gz")
            DISK_FORMAT=raw
            CONTAINER_FORMAT=bare
            UNPACK=zcat
            ;;
        *.qcow2)
            IMAGE="$FILES/${IMAGE_FNAME}"
            IMAGE_NAME=$(basename "$IMAGE" ".qcow2")
            DISK_FORMAT=qcow2
            CONTAINER_FORMAT=bare
            ;;
        *.iso)
            IMAGE="$FILES/${IMAGE_FNAME}"
            IMAGE_NAME=$(basename "$IMAGE" ".iso")
            DISK_FORMAT=iso
            CONTAINER_FORMAT=bare
            ;;
        *) echo "Do not know what to do with $IMAGE_FNAME"; false;;
    esac

    # Check for an image already loaded before doing a create
    id=$( get_image_id $IMAGE_NAME )
    if ! [ "x${id}" = "x" ]; then
        return
    fi

    if [ "$CONTAINER_FORMAT" = "bare" ]; then
        if [ "$UNPACK" = "zcat" ]; then
            glance $token_arg \
                   --os-image-url http://$GLANCE_HOSTPORT \
                   image-create \
                   --name "$IMAGE_NAME" \
                   --public \
                   --container-format=$CONTAINER_FORMAT \
                   --disk-format $DISK_FORMAT < <(zcat --force "${IMAGE}")
        else
            glance $token_arg \
                   --os-image-url http://$GLANCE_HOSTPORT \
                   image-create \
                   --name "$IMAGE_NAME" \
                   --public \
                   --container-format=$CONTAINER_FORMAT \
                   --disk-format $DISK_FORMAT < "${IMAGE}"
        fi
    else
        # Use glance client to add the kernel the root filesystem.
        # We parse the results of the first upload to get the glance ID of the
        # kernel for use when uploading the root filesystem.
        KERNEL_ID=""; RAMDISK_ID="";
        if [ -n "$KERNEL" ]; then
            KERNEL_ID=$(glance $token_arg --os-image-url http://$GLANCE_HOSTPORT image-create --name "$IMAGE_NAME-kernel" --public --container-format aki --disk-format aki < "$KERNEL" | grep ' id ' | get_field 2)
        fi
        if [ -n "$RAMDISK" ]; then
            RAMDISK_ID=$(glance $token_arg --os-image-url http://$GLANCE_HOSTPORT image-create --name "$IMAGE_NAME-ramdisk" --public --container-format ari --disk-format ari < "$RAMDISK" | grep ' id ' | get_field 2)
        fi
        glance $token_arg \
               --os-image-url http://$GLANCE_HOSTPORT \
               image-create \
               --name "${IMAGE_NAME%.img}" \
               --public \
               --container-format ami \
               --disk-format ami \
               ${KERNEL_ID:+--property kernel_id=$KERNEL_ID} \
               ${RAMDISK_ID:+--property ramdisk_id=$RAMDISK_ID} < "${IMAGE}"
    fi
}



# Keep track of the current directory
#TOOLS_DIR=$(cd $(dirname "$0") && pwd)
#TOP_DIR=$(cd $TOOLS_DIR/..; pwd)

## Import common functions
#source $TOP_DIR/functions

## Import configuration
#source $TOP_DIR/openrc "" "" "" ""

## Find the cache dir
#FILES=$TOP_DIR/files

FILES=/tmp

if [[ -z "$1" ]]; then
    usage
fi

# Get a token to authenticate to glance
TOKEN=$(keystone token-get | grep ' id ' | get_field 2)

# Glance connection info.  Note the port must be specified.
GLANCE_HOST=${GLANCE_HOST:-localhost}
GLANCE_HOSTPORT=${GLANCE_HOSTPORT:-$GLANCE_HOST:9292}

for IMAGE in "$*"; do
    upload_image $IMAGE $TOKEN
done
