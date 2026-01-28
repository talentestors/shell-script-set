#!/bin/bash
#
# https://github.com/haoduck/iptables-allow-cloudflare-ip-addresses/
# ipset

if [[ -z "$(command -v iptables)" ]] || [[ -z "$(command -v ip6tables)" ]];then
    echo "Error: iptables/ip6tables not found!"
    echo "Please install it."
    echo "Example: apt install -y iptables"
    echo "         yum install -y iptables"
    exit 1
fi

if ! command -v ipset &>/dev/null; then
    echo "❌ Error: ipset not found"
    echo "   Example: apt install -y ipset"
    exit 1
fi

# 创建 ipset 集合
ipset create cf-ipv4 hash:net family inet 2>/dev/null || true
ipset create cf-ipv6 hash:net family inet6 2>/dev/null || true

if [[ -z "$(iptables -L |grep 'Chain CLOUDFLARE')" ]];then
    echo "创建 CLOUDFLARE 绑定到 1PANEL_INPUT"
    iptables -N CLOUDFLARE
    echo "1PANEL_INPUT <= CLOUDFLARE"
    iptables -I 1PANEL_INPUT 1 -j CLOUDFLARE
    # 添加 ipset 规则
    iptables -A CLOUDFLARE -m set --match-set cf-ipv4 src -p tcp -m multiport --dport http,https -j ACCEPT
    iptables -A CLOUDFLARE -m set --match-set cf-ipv4 src -p udp -m multiport --dport https -j ACCEPT
    echo "CLOUDFLARE: 已添加 ipset 规则 (cf-ipv4)"
fi
if [[ -z "$(ip6tables -L |grep 'Chain CLOUDFLARE')" ]];then
    echo "创建 CLOUDFLARE 绑定到 INPUT - v6"
    ip6tables -N CLOUDFLARE
    echo "INPUT <= CLOUDFLARE"
    ip6tables -I INPUT 1 -j CLOUDFLARE

    echo "http,https => DROP"
    ip6tables -D INPUT -p tcp -m multiport --dport http,https -j DROP 2>/dev/null  
    ip6tables -D INPUT -p udp -m multiport --dport https -j DROP 2>/dev/null
    ip6tables -A INPUT -p tcp -m multiport --dport http,https -j DROP
    ip6tables -A INPUT -p udp -m multiport --dport https -j DROP

    # 添加 ipset 规则
    ip6tables -A CLOUDFLARE -m set --match-set cf-ipv6 src -p tcp -m multiport --dport http,https -j ACCEPT
    ip6tables -A CLOUDFLARE -m set --match-set cf-ipv6 src -p udp -m multiport --dport https -j ACCEPT
    echo "CLOUDFLARE: 已添加 ipset 规则 (cf-ipv6)"
fi

run(){
    iptables=$1
    ips=$2
    rule_file=$3
    chain=$4

    # 清空 ipset 集合
    if [[ "$iptables" == "iptables" ]]; then
        ipset flush cf-ipv4
        echo "Clear ipset cf-ipv4"
        while IFS= read -r ip; do [[ -n "$ip" ]] && ipset add cf-ipv4 "$ip" 2>/dev/null && echo "cf-ipv4 <== $ip"; done <<< "$ips"
    else
        ipset flush cf-ipv6
        echo "Clear ipset cf-ipv6"
        while IFS= read -r ip; do [[ -n "$ip" ]] && ipset add cf-ipv6 "$ip" 2>/dev/null && echo "cf-ipv6 <== $ip"; done <<< "$ips"
    fi

    #保存规则
    $iptables-save > $rule_file
    echo "Save to $rule_file"
}

#这里对curl的结果做一次判断，避免网络出问题时可能导致的问题。如果curl的结果中没找到xxx.xxx.xxx.xxx/xx或者xxxx:xxxx::/xx的内容就不执行
ips_v4=$(curl -s https://www.cloudflare.com/ips-v4|grep -Eo "([0-9]{1,3}.){3}[0-9]{1,3}/[0-9]{1,3}")
ips_v6=$(curl -s https://www.cloudflare.com/ips-v6|grep -Eo "([a-z0-9]{1,4}:){1,7}:?/[0-9]{1,3}")

mkdir -p /etc/iptables/

if [[ "$ips_v4" ]];then
    echo "LOAD IPv4"
    run "iptables" "$ips_v4" "/etc/iptables/rules.v4" "1PANEL_INPUT"
fi

if [[ "$ips_v6" ]];then
    echo "LOAD IPv6"
    run "ip6tables" "$ips_v6" "/etc/iptables/rules.v6" "INPUT"
fi

ipset save > /etc/ipset.rules 2>/dev/null && echo "Save ipset > /etc/ipset.rules" || echo "Warning: ipset save failed"

echo "✅ Done"
