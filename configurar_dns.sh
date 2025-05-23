#!/bin/bash

# ========== Verificar se o usuário é root ==========
if [ "$EUID" -ne 0 ]; then
    echo "Execute este script como root ou usando sudo."
    exit 1
fi

# ========== Verificar se dialog está instalado ==========
if ! command -v dialog &> /dev/null; then
    echo "Instalando dialog..."
    apt update && apt install -y dialog
fi

# ========== Caminhos ==========
CONF_LOCAL="/etc/bind/named.conf.local"
CONF_OPTIONS="/etc/bind/named.conf.options"
DIR_ZONA="/etc/bind"
ARQ_DOMINIO="/tmp/dns_zona_direta.txt"
ARQ_REDE="/tmp/dns_zona_reversa.txt"

# Carrega domínio e rede (se existirem)
DOMINIO=$( [ -f "$ARQ_DOMINIO" ] && cat "$ARQ_DOMINIO" || echo "" )
REDE=$( [ -f "$ARQ_REDE" ] && cat "$ARQ_REDE" || echo "" )

# ========== Função para instalar o BIND9 com barra de progresso ==========
instalar_bind() {
    apt-get update -qq

    (apt-get install -y bind9 bind9utils bind9-doc > /tmp/bind_install.log 2>&1) &
    PID=$!

    {
        while kill -0 $PID 2>/dev/null; do
            for i in $(seq 0 100); do
                echo $i
                sleep 0.05
                kill -0 $PID 2>/dev/null || break
            done
        done
        echo 100
    } | dialog --gauge "Instalando BIND9 DNS Server..." 10 60 0

    wait $PID
    RET=$?

    if [ $RET -eq 0 ]; then
        dialog --msgbox "BIND9 instalado com sucesso!" 6 50
    else
        dialog --msgbox "Erro na instalação. Veja /tmp/bind_install.log" 8 60
        exit 1
    fi
}

# ========== Verificar se está instalado ==========
verifica_bind() {
    if dpkg-query -W -f='${Status}' bind9 2>/dev/null | grep -q "install ok installed"; then
        return 0
    else
        return 1
    fi
}

# ========== Calcula zona reversa ==========
calc_zona_reversa() {
    echo "$REDE" | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}'
}

# ========== Atualiza named.conf.local ==========
atualiza_named_conf_local() {
    cat > "$CONF_LOCAL" <<EOF
// Arquivo gerado automaticamente

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

# ========== Cria zona direta ==========
cria_zona_direta() {
    local ip_srv=$(hostname -I | awk '{print $1}')
    cat > "$DIR_ZONA/db.$DOMINIO" <<EOF
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

# ========== Cria zona reversa ==========
cria_zona_reversa() {
    local zona_rev=$(echo $REDE | tr '.' '-')
    local ip_srv=$(hostname -I | awk '{print $1}')
    local ultimo_octeto=$(echo "$ip_srv" | awk -F. '{print $4}')
    cat > "$DIR_ZONA/db.$zona_rev" <<EOF
\$TTL    604800
@       IN      SOA     $DOMINIO. root.$DOMINIO. (
                              2         ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      $DOMINIO.
$ultimo_octeto       IN      PTR     $DOMINIO.
EOF
}

# ========== Configura named.conf.options ==========
configura_named_conf_options() {
    IP_SERVIDOR=$(dialog --stdout --inputbox "Digite o IP do servidor DNS (ex: 192.168.0.1):" 8 50)
    [ -z "$IP_SERVIDOR" ] && return
    REDE_LOCAL=$(dialog --stdout --inputbox "Digite a rede local (ex: 192.168.0.0/24):" 8 50)
    [ -z "$REDE_LOCAL" ] && return

    cat > "$CONF_OPTIONS" <<EOF
options {
    directory "/var/cache/bind";

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
    systemctl restart bind9
}

# ========== Gerenciar /etc/resolv.conf ==========
gerenciar_resolv_conf() {
    while true; do
        OP=$(dialog --stdout --menu "Gerenciar resolv.conf" 15 60 4 \
            1 "Adicionar DNS" \
            2 "Remover DNS" \
            0 "Voltar")

        case $OP in
            1)
                DOM=$(dialog --stdout --inputbox "Digite o domínio:" 8 40)
                IP=$(dialog --stdout --inputbox "Digite o IP:" 8 40)
                echo "nameserver $IP" >> /etc/resolv.conf
                echo "search $DOM" >> /etc/resolv.conf
                dialog --msgbox "Adicionado $IP ($DOM) ao resolv.conf" 6 50
                ;;
            2)
                LINHAS=$(grep -n "nameserver\|search" /etc/resolv.conf | awk -F: '{print $1 " " $2}')
                if [ -z "$LINHAS" ]; then
                    dialog --msgbox "Nenhuma entrada encontrada." 6 40
                else
                    LINHA=$(echo "$LINHAS" | dialog --stdout --menu "Selecione para remover:" 20 60 10 $(echo "$LINHAS"))
                    [ -z "$LINHA" ] || sed -i "${LINHA}d" /etc/resolv.conf
                    dialog --msgbox "Entrada removida." 6 40
                fi
                ;;
            0) break ;;
        esac
    done
}

# ========== Menu principal ==========
while true; do
    OPCAO=$(dialog --stdout --menu "📡 Gerenciador DNS" 15 60 6 \
        1 "Instalar DNS (BIND9)" \
        2 "Configurar DNS" \
        3 "Gerenciar resolv.conf" \
        0 "Sair")

    case $OPCAO in
        1)
            if verifica_bind; then
                dialog --msgbox "BIND9 já está instalado." 6 50
            else
                instalar_bind
            fi
            ;;
        2)
            while true; do
                DOMINIO_ATUAL=${DOMINIO:-"nenhuma"}
                REDE_ATUAL=${REDE:-"nenhuma"}

                SUB_OPCAO=$(dialog --stdout --menu "⚙️ Configuração DNS" 15 60 5 \
                    1 "Configurar Zona Direta (atual: $DOMINIO_ATUAL)" \
                    2 "Configurar Zona Reversa (atual: $REDE_ATUAL)" \
                    3 "Configurar named.conf.options" \
                    4 "Aplicar e Reiniciar DNS" \
                    0 "Voltar")

                case $SUB_OPCAO in
                    1)
                        DOMINIO_NOVO=$(dialog --stdout --inputbox "Informe o nome da zona direta (ex: exemplo.local):" 8 50 "$DOMINIO")
                        [ -z "$DOMINIO_NOVO" ] && continue
                        DOMINIO="$DOMINIO_NOVO"
                        echo "$DOMINIO" > "$ARQ_DOMINIO"
                        cria_zona_direta
                        atualiza_named_conf_local
                        dialog --msgbox "Zona direta configurada para $DOMINIO" 6 50
                        ;;
                    2)
                        REDE_NOVA=$(dialog --stdout --inputbox "Informe os 3 primeiros octetos da rede (ex: 192.168.0):" 8 50 "$REDE")
                        [ -z "$REDE_NOVA" ] && continue
                        REDE="$REDE_NOVA"
                        echo "$REDE" > "$ARQ_REDE"
                        cria_zona_reversa
                        atualiza_named_conf_local
                        dialog --msgbox "Zona reversa configurada para $(calc_zona_reversa)" 6 60
                        ;;
                    3)
                        configura_named_conf_options
                        ;;
                    4)
                        systemctl restart bind9
                        dialog --msgbox "BIND9 reiniciado com sucesso!" 6 50
                        ;;
                    0) break ;;
                esac
            done
            ;;
        3) gerenciar_resolv_conf ;;
        0) clear; exit ;;
    esac
done
