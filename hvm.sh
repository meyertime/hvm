#!/bin/bash
set -e

os=${HVM_OS:-linux}
arch=${HVM_ARCH:-amd64}

first_arg=$1
second_arg=$2
version_arg=$3

action_arg=
product_arg=

action=
product=
version=
versions=
versions_html=
versions_str=
selected_versions=

base_dir="$HOME/.hvm"
artifacts_dir="$base_dir/artifacts"
bin_dir="$base_dir/bin"
artifact_os=
artifact_arch=
artifact_name=
artifact_url=

function usage() {
    echo "Usage: hvm action product [version]"
    echo
    echo "Actions: install (i), ls, ls-remote (lsr), use (u), use-remote (ur)"
    echo "Products: terraform (tf)"
    echo "Version: Can be a specific version, part of a version, or omitted for latest"
    echo
    return 1
}

function interpret_args() {
    if [ "$first_arg" == "" ]; then usage; fi
    if [ "$second_arg" == "" ]; then usage; fi

    action_arg=$first_arg
    product_arg=$second_arg
    get_action
    get_product

    if [ "$action$product" == "" ]; then
        action_arg=$second_arg
        product_arg=$first_arg
        get_action
        get_product
    fi

    if [ "$action$product" == "" ]; then
        echo "Unrecognized action or product: $first_arg"
        echo "Unrecognized action or product: $second_arg"
        return 1
    elif [ "$action" == "" ]; then
        echo "Unrecognized action: $action_arg"
        return 1
    elif [ "$product" == "" ]; then
        echo "Unrecognized product: $product_arg"
        return 1
    fi
}

function get_action() {
    if [[ "$action_arg" =~ ^(install|i)$ ]]; then
        action=install
    elif [[ "$action_arg" =~ ^(ls)$ ]]; then
        action=ls
    elif [[ "$action_arg" =~ ^(ls-remote|lsr)$ ]]; then
        action=ls_remote
    elif [[ "$action_arg" =~ ^(use|u)$ ]]; then
        action=use
    elif [[ "$action_arg" =~ ^(use-remote|ur)$ ]]; then
        action=use_remote
    elif [[ "$action_arg" =~ ^(version|v)$ ]]; then
        action=version
    elif [[ "$action_arg" =~ ^(version-remote|vr)$ ]]; then
        action=version_remote
    fi
}

function get_product() {
    if [[ "$product_arg" =~ ^consul$ ]]; then
        product=consul
    elif [[ "$product_arg" =~ ^nomad$ ]]; then
        product=nomad
    elif [[ "$product_arg" =~ ^packer$ ]]; then
        product=packer
    elif [[ "$product_arg" =~ ^(terraform|tf)$ ]]; then
        product=terraform
    elif [[ "$product_arg" =~ ^vagrant$ ]]; then
        product=vagrant
    elif [[ "$product_arg" =~ ^vault$ ]]; then
        product=vault
    fi
}

function get_versions_remote() {
    versions_html=${versions_html:-$(curl -s "https://releases.hashicorp.com/$product/")}

    versions_str=`echo "$versions_html" | awk 'match($0, /<a href="\/'$product'\/([0-9]+(\.[0-9]+){1,3})\/?"/, a) {print a[1]}'`
    if [ "$versions_str" == "" ]; then
        echo "Could not find any version of $product"
        return 1
    fi
}

function get_version_artifact_remote() {
    html=`curl -s "https://releases.hashicorp.com/$product/$version/"`

    arches_str=`echo "$html" | awk 'match($0, /<a data-product="'$product'" data-version="'$version'" data-os="'$os'" data-arch="'$arch'" href="(\/[^"]+)"/, a) {print a[1]}'`
    IFS=$'\n' read -ra arches <<< "$arches_str"
    arch_url=${arches[0]}

    if [ "$arch_url" == "" ]; then
        echo "Could not find an artifact for $product v$version $os $arch"
        return 1
    fi

    artifact_os=$os
    artifact_arch=$arch
    artifact_url=$arch_url
    artifact_name=`basename $arch_url`
}

function get_versions_remote() {
    versions_html=${versions_html:-$(curl -s "https://releases.hashicorp.com/$product/")}

    versions_str=`echo "$versions_html" | awk 'match($0, /<a href="\/'$product'\/([0-9]+\.[0-9]+\.[0-9]+(-.+)?)\/?"/, a) {print a[1]}'`
    if [ "${versions_str[0]}" == "" ]; then
        echo "Could not find any version of $product"
        return 1
    fi
}

function get_versions_local() {
    versions_str=`ls -1 "$base_dir/$product/" | grep -P '^\d+\.\d+\.\d+(-.+)?$'`
}

function select_versions() {
    if [ "$version_arg" == "" ]; then
        selected_versions=$versions_str
    elif [ "$version_arg" == "latest" ]; then
        selected_versions=`echo "$versions_str" | grep -P '^\d+\.\d+\.\d+$' | sort -Vr | head -n 1`
    else
        code=0
        echo "$versions_str" | grep -Fx "$version_arg" || code=$?
        if [ "$code" == "0" ]; then
            selected_versions=${version_arg}
        else
            selected_versions=`echo "$versions_str" | grep -P '^\d+\.\d+\.\d+$' | grep -P "^\\Q${version_arg//\\E/\\\\E}.\\E" || code=$?`
        fi
    fi

    if [ "$selected_versions" == "" ]; then
        echo "Could not find version of $product: $version_arg"
        return 1
    fi
}

function select_version() {
    select_versions
    
    if [ "$version_arg" == "" ]; then
        version=`echo "$selected_versions" | grep -P '^\d+\.\d+\.\d+$' | sort -Vr | head -n 1`
    else
        version=`echo "$selected_versions" | sort -Vr | head -n 1`
    fi
}

function action_install() {
    product_dir="$install_dir/$product"

    get_versions_remote
    select_version

    echo "Installing version $version of $product..."

    get_version_artifact_remote

    artifact_path="$artifacts_dir/$artifact_name"
    if [ -f $artifact_path ]; then
        echo "Artifact already downloaded: $artifact_name"
    else
        echo "Downloading artifact: $artifact_name"
        mkdir -p "$artifacts_dir"
        curl "https://releases.hashicorp.com$artifact_url" -o $artifact_path
    fi

    if [[ "$artifact_name" =~ \.zip$ ]]; then
        install_dir="$base_dir/$product/$version"
        bin_path="$install_dir/$product"
        
        if [ -f $bin_path ]; then
            echo "Already installed: $artifact_name"
        else
            echo "Extracting artifact: $artifact_name"
            mkdir -p $install_dir
            unzip -oq $artifact_path -d $install_dir

            if [ -f $bin_path ]; then
                chmod +x $bin_path
                mkdir -p $bin_dir
                ln -srfT $bin_path "$bin_dir/$product-$version"
            else
                echo "Warning: Expected executable file to exist, but it does not: $bin_path"
            fi
        fi
    else
        echo "Don't know how to install $artifact_name"
        return 1
    fi

    echo "Installed successfully"
}

function action_ls() {
    get_versions_local
    select_versions
    echo "${selected_versions}" | sort -V
}

function action_ls_remote() {
    get_versions_remote
    select_versions
    echo "${selected_versions}" | sort -V
}

function action_use() {
    if [ "$version_arg" == "" ]; then
        echo "Version is required for action: use"
        return 1
    fi
    get_versions_local
    select_version

    bin_path="$base_dir/$product/$version/$product"
    if [ ! -f $bin_path ]; then
        echo "Version of $product is not installed: $version"
    fi

    ln -srfT $bin_path "$bin_dir/$product"

    echo "Using version $version of $product"
}

function action_use_remote() {
    if [ "$version_arg" == "" ]; then
        echo "Version is required for action: use-remote"
        return 1
    fi
    get_versions_remote
    select_version

    bin_path="$base_dir/$product/$version/$product"
    if [ ! -f $bin_path ]; then
        version_arg=${version}
        action_install
    fi

    ln -srfT $bin_path "$bin_dir/$product"

    echo "Using version $version of $product"
}

function action_version() {
    get_versions_local
    select_version
    echo "${version}"
}

function action_version_remote() {
    get_versions_remote
    select_version
    echo "${version}"
}

interpret_args
action_$action
