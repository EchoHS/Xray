get_latest_version() {
    unset is_sh_download_ref
    case $1 in
    core)
        name=$is_core_name
        url="https://api.github.com/repos/${is_core_repo}/releases/latest?v=$RANDOM"
        ;;
    sh)
        name="$is_core_name 脚本"
        url="https://api.github.com/repos/$is_sh_repo/releases/latest?v=$RANDOM"
        sh_main_url="https://raw.githubusercontent.com/$is_sh_repo/main/xray.sh?v=$RANDOM"
        ;;
    caddy)
        name="Caddy"
        url="https://api.github.com/repos/$is_caddy_repo/releases/latest?v=$RANDOM"
        ;;
    esac
    latest_ver=$(_wget -qO- "$url" 2>/dev/null | grep tag_name | grep -E -o 'v([0-9.]+)')
    [[ ! $latest_ver && $(type -P curl) ]] && latest_ver=$(_curl "$url" | grep tag_name | grep -E -o 'v([0-9.]+)')
    if [[ $1 == 'sh' ]]; then
        sh_main_ver=$(_wget -qO- "$sh_main_url" 2>/dev/null | sed -n 's/^is_sh_ver=\(v[0-9][0-9.]*\).*/\1/p')
        [[ ! $sh_main_ver && $(type -P curl) ]] && sh_main_ver=$(_curl "$sh_main_url" 2>/dev/null | sed -n 's/^is_sh_ver=\(v[0-9][0-9.]*\).*/\1/p')
        sh_use_main=
        if [[ $sh_main_ver && ! $latest_ver ]]; then
            sh_use_main=1
        elif [[ $sh_main_ver && $sh_main_ver != $latest_ver ]]; then
            sh_newest_ver=$(printf '%s\n%s\n' "$latest_ver" "$sh_main_ver" | sort -V | tail -n1)
            [[ $sh_newest_ver == "$sh_main_ver" ]] && sh_use_main=1
        fi
        if [[ $sh_use_main ]]; then
            latest_ver=$sh_main_ver
            is_sh_download_ref=main
        fi
    fi
    [[ ! $latest_ver ]] && {
        err "获取 ${name} 最新版本失败."
    }
    unset name url sh_main_url sh_main_ver sh_newest_ver sh_use_main
}
download() {
    latest_ver=$2
    [[ ! $latest_ver && $1 != 'dat' ]] && get_latest_version $1
    # tmp dir
    make_tmpdir || err "create temp dir failed: $tmpdir"
    case $1 in
    core)
        name=$is_core_name
        tmpfile=$tmpdir/$is_core.zip
        link="https://github.com/${is_core_repo}/releases/download/${latest_ver}/${is_core}-linux-${is_core_arch}.zip"
        download_file
        unzip -qo $tmpfile -d $is_core_dir/bin
        chmod +x $is_core_bin
        ;;
    sh)
        name="$is_core_name 脚本"
        tmpfile=$tmpdir/sh.zip
        if [[ $is_sh_download_ref == 'main' ]]; then
            link="https://github.com/${is_sh_repo}/archive/refs/heads/main.zip"
        else
            link="https://github.com/${is_sh_repo}/releases/download/${latest_ver}/code.zip"
        fi
        download_file
        is_sh_extract_dir=$tmpdir/sh
        mkdir -p "$is_sh_extract_dir"
        unzip -qo "$tmpfile" -d "$is_sh_extract_dir" || err "解压 ${name} 失败."
        is_sh_source_dir=$is_sh_extract_dir
        if [[ ! -f "$is_sh_source_dir/xray.sh" ]]; then
            is_sh_source_dir=$(find "$is_sh_extract_dir" -mindepth 1 -maxdepth 1 -type d | head -n1)
        fi
        [[ ! -f "$is_sh_source_dir/xray.sh" || ! -d "$is_sh_source_dir/src" ]] && err "${name} 更新包格式无效."
        cp -rf "$is_sh_source_dir"/. "$is_sh_dir"/
        chmod +x $is_sh_bin
        unset is_sh_extract_dir is_sh_source_dir
        ;;
    dat)
        name="geoip.dat"
        tmpfile=$tmpdir/geoip.dat
        link="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat"
        download_file
        name="geosite.dat"
        tmpfile=$tmpdir/geosite.dat
        link="https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat"
        download_file
        cp -f $tmpdir/*.dat $is_core_dir/bin/
        ;;
    caddy)
        name="Caddy"
        tmpfile=$tmpdir/caddy.tar.gz
        # https://github.com/caddyserver/caddy/releases/download/v2.6.4/caddy_2.6.4_linux_amd64.tar.gz
        link="https://github.com/${is_caddy_repo}/releases/download/${latest_ver}/caddy_${latest_ver:1}_linux_${caddy_arch}.tar.gz"
        download_file
        [[ ! $(type -P tar) ]] && {
            rm -rf $tmpdir
            err "请安装 tar"
        }
        tar zxf $tmpfile -C $tmpdir
        cp -f $tmpdir/caddy $is_caddy_bin
        chmod +x $is_caddy_bin
        ;;
    esac
    rm -rf $tmpdir
    unset latest_ver is_sh_download_ref
}
download_file() {
    rm -f "$tmpfile"
    if ! _wget -t 5 "$link" -O "$tmpfile" || [[ ! -s $tmpfile ]]; then
        rm -f "$tmpfile"
        if [[ $(type -P curl) ]] && _curl --connect-timeout 15 --retry 5 --retry-delay 1 "$link" -o "$tmpfile" && [[ -s $tmpfile ]]; then
            return
        fi
        avail_kb=$(df -Pk "$tmpdir" 2>/dev/null | awk 'NR==2 {print $4}')
        [[ $avail_kb =~ ^[0-9]+$ && $avail_kb -lt 20480 ]] && err "\ntemp dir low disk space: $tmpdir\n"
        rm -rf $tmpdir
        err "\n下载 ${name} 失败.\n"
    fi
}
