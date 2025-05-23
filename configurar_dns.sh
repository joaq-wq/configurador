#!/bin/bash

# Script DNS Interativo com dialog e configuração completa
# Instalação bind9 com barra de progresso dinâmica refletindo progresso real
# Configuração das zonas, named.conf e resolv.conf interativo

# Verifica e instala dialog se necessário (sem saída no terminal)
if ! command -v dialog &>/dev/null; then
    apt-get update -qq
    apt-get install -y dialog >/dev/null 2>&1
fi

CONF_LOCAL="/etc/bind/named.conf.local"
CONF_OPTIONS="/etc/bind/named.conf.options"
DIR_ZONA="/etc/bind"

ARQ_DOMINIO="/tmp/dns_zona_direta.txt"
ARQ_REDE="/tmp/dns_zona_reversa.txt"

DOMINIO=$( [ -f "$ARQ_DOMINIO" ] && cat "$ARQ_DOMINIO" || echo "" )
REDE=$( [ -f "$ARQ_REDE" ] && cat "$ARQ_REDE" || echo "" )

calc_zona_reversa() {
    echo "$REDE" | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}'
}

atualiza_named_conf_local() {
    sudo bash -c "cat > $CONF_LOCAL" <<EOF
// Configuração automática gerada pelo script

zone "$DOMINIO" {
    type master;
    file "$DIR_ZONA/db.$DOMINIO";
};

zone "$(calc_zona_reversa)" {
    type master;
    file "$DIR_ZONA/db.$(echo $REDE | tr '.' '-')"; 
};
EOF
}

cria_zona_direta() {
    local ip_srv=$(hostname -I | awk '{print $1}')
    sudo bash -c "cat > $DIR_ZONA/db.$DOMINIO" <<EOF
\$TTL    604800
@       IN      SOA     $DOMINIO. root.$DOMINIO. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      $DOMINIO.
@       IN      A       $ip_srv
www     IN      A       $ip_srv
ftp     IN      A       $ip_srv
EOF
}

cria_zona_reversa() {
    local zona_rev=$(echo $REDE | tr '.' '-')
    local ip_srv=$(hostname -I | awk '{print $1}')
    sudo bash -c "cat > $DIR_ZONA/db.$zona_rev" <<EOF
\$TTL    604800
@       IN      SOA     $DOMINIO. root.$DOMINIO. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      $DOMINIO.
1       IN      PTR     $DOMINIO.
EOF
}

configura_named_conf_options() {
    IP_SERVIDOR=$(dialog --stdout --inputbox "Digite o IP do servidor DNS (ex: 192.168.0.1):" 8 50)
    [ -z "$IP_SERVIDOR" ] && return
    REDE_LOCAL=$(dialog --stdout --inputbox "Digite a rede local (ex: 192.168.0.0/24):" 8 50)
    [ -z "$REDE_LOCAL" ] && return

    sudo bash -c "cat > $CONF_OPTIONS" <<EOF
options {
    directory \"/var/cache/bind\";

    recursion yes;
    allow-recursion { 127.0.0.1; $REDE_LOCAL; };
    allow-query { 127.0.0.1; $REDE_LOCAL; };

    listen-on { 127.0.0.1; $IP_SERVIDOR; };

    forwarders {
        8.8.8.8;
        8.8.4.4;
    };

    dnssec-validation auto;

    auth-nxdomain no;
    listen-on-v6 { any; };
};
EOF

    dialog --msgbox "Arquivo named.conf.options atualizado." 6 50
    sudo systemctl restart bind9
}

configura_resolv_conf() {
    while true; do
        RESOLV_OPC=$(dialog --stdout --menu "Gerenciar /etc/resolv.conf" 12 50 3 \
            1 "Adicionar nameserver" \
            2 "Remover nameserver" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $RESOLV_OPC in
            1)
                NOME_DOMINIO=$(dialog --stdout --inputbox "Digite o domínio de busca:" 8 50)
                [ -z "$NOME_DOMINIO" ] && continue
                NS_IP=$(dialog --stdout --inputbox "Digite o IP do nameserver:" 8 50)
                [ -z "$NS_IP" ] && continue

                # Se resolv.conf não existir, cria
                [ ! -f /etc/resolv.conf ] && sudo touch /etc/resolv.conf

                # Adiciona linha nameserver e search no arquivo, se não existir
                sudo sed -i "/^search /d" /etc/resolv.conf
                echo "search $NOME_DOMINIO" | sudo tee -a /etc/resolv.conf >/dev/null
                echo "nameserver $NS_IP" | sudo tee -a /etc/resolv.conf >/dev/null

                dialog --msgbox "Nameserver $NS_IP para domínio $NOME_DOMINIO adicionado." 6 50
                ;;
            2)
                # Lista nameservers existentes
                MAP_NS=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null)
                MAP_SEARCH=$(grep "^search" /etc/resolv.conf 2>/dev/null)

                if [ -z "$MAP_NS" ]; then
                    dialog --msgbox "Nenhum nameserver encontrado em /etc/resolv.conf" 6 50
                    continue
                fi

                # Cria menu para remover
                OPTIONS=()
                i=1
                while read -r line; do
                    OPTIONS+=("$i" "$line")
                    ((i++))
                done <<< "$MAP_NS"

                SEL=$(dialog --stdout --menu "Escolha nameserver para remover:" 12 50 "${#OPTIONS[@]}" "${OPTIONS[@]}")
                [ -z "$SEL" ] && continue

                # Remove a linha selecionada do resolv.conf
                REMOVE_LINE=$(echo "$MAP_NS" | sed -n "${SEL}p")
                sudo sed -i "\|$REMOVE_LINE|d" /etc/resolv.conf

                dialog --msgbox "Nameserver removido: $REMOVE_LINE" 6 50
                ;;
            0) break ;;
        esac
    done
}

verifica_bind_instalado() {
    dpkg-query -W -f='${Status}' bind9 2>/dev/null | grep -q "install ok installed"
}

instalar_bind() {
    TMP_LOG="/tmp/bind_install.log"
    rm -f "$TMP_LOG"

    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y bind9 bind9utils bind9-doc >"$TMP_LOG" 2>&1 &
    PID=$!

    while kill -0 $PID 2>/dev/null; do
        LINES=$(wc -l < "$TMP_LOG")
        PERCENT=$(( LINES > 100 ? 100 : LINES ))
        echo $PERCENT
        sleep 0.2
    done
    echo 100
    wait $PID
    RET=$?

    if [ $RET -eq 0 ]; then
        dialog --msgbox "BIND9 instalado com sucesso!" 6 50
    else
        dialog --msgbox "Erro na instalação. Veja $TMP_LOG" 8 60
        exit 1
    fi
}

while true; do
    DOMINIO_ATUAL=${DOMINIO:-"nenhuma"}
    REDE_ATUAL=${REDE:-"nenhuma"}

    OPCAO=$(dialog --stdout --menu "📡 Configuração DNS" 15 60 6 \
        1 "Instalar BIND9" \
        2 "Configurar Zona Direta (atual: $DOMINIO_ATUAL)" \
        3 "Configurar Zona Reversa (atual: $REDE_ATUAL)" \
        4 "Configurar named.conf.options" \
        5 "Gerenciar /etc/resolv.conf" \
        6 "Aplicar configurações e reiniciar BIND" \
        0 "Sair")

    [ $? -ne 0 ] && break

    case $OPCAO in
        1)
            instalar_bind
            ;;
        2)
            DOMINIO_NOVO=$(dialog --stdout --inputbox "Informe o nome da zona direta (ex: grau.local):" 8 50 "$DOMINIO")
            [ -z "$DOMINIO_NOVO" ] && continue
            DOMINIO="$DOMINIO_NOVO"
            echo "$DOMINIO" > "$ARQ_DOMINIO"
            cria_zona_direta
            atualiza_named_conf_local
            dialog --msgbox "Zona direta configurada para $DOMINIO" 6 50
            ;;
        3)
            REDE_NOVA=$(dialog --stdout --inputbox "Informe os 3 primeiros octetos da rede (ex: 192.168.0):" 8 50 "$REDE")
            [ -z "$REDE_NOVA" ] && continue
            REDE="$REDE_NOVA"
            echo "$REDE" > "$ARQ_REDE"
            cria_zona_reversa
            atualiza_named_conf_local
            dialog --msgbox "Zona reversa configurada para rede $REDE" 6 50
            ;;
        4)
            configura_named_conf_options
            ;;
        5)
            configura_resolv_conf
            ;;
        6)
            sudo systemctl restart bind9
            dialog --msgbox "BIND9 reiniciado com as configurações atuais." 6 50
            ;;
        0)
            clear
            exit 0
            ;;
    esac
done
