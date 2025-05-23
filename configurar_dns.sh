#!/bin/bash

# Script DNS Interativo com dialog e configuração completa

# Verificar se dialog está instalado
if ! command -v dialog &> /dev/null; then
    echo "Instalando dialog..."
    apt update -qq
    apt install -y dialog
fi

# Variáveis
CONF_LOCAL="/etc/bind/named.conf.local"
CONF_OPTIONS="/etc/bind/named.conf.options"
DIR_ZONA="/etc/bind"

ARQ_DOMINIO="/tmp/dns_zona_direta.txt"
ARQ_REDE="/tmp/dns_zona_reversa.txt"

# Carrega dados salvos, se houver
DOMINIO=$( [ -f "$ARQ_DOMINIO" ] && cat "$ARQ_DOMINIO" || echo "" )
REDE=$( [ -f "$ARQ_REDE" ] && cat "$ARQ_REDE" || echo "" )

# Função para calcular zona reversa
calc_zona_reversa() {
    echo "$REDE" | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}'
}

# Instalar BIND9 com barra de progresso dinâmica
instalar_bind9() {
    if dpkg -l | grep -qw bind9; then
        dialog --msgbox "✅ BIND9 já está instalado." 6 40
        return
    fi

    apt update -qq

    (
    apt install -y bind9 bind9utils bind9-doc > /tmp/bind_install.log 2>&1 &
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
    } | dialog --gauge "📦 Instalando BIND9 DNS Server..." 10 60 0

    wait $PID
    RET=$?

    if [ $RET -eq 0 ]; then
        dialog --msgbox "✅ BIND9 instalado com sucesso!" 6 50
    else
        dialog --msgbox "❌ Erro na instalação. Veja /tmp/bind_install.log" 8 60
        exit 1
    fi
    )
}

# Atualizar named.conf.local
atualiza_named_conf_local() {
    sudo bash -c "cat > $CONF_LOCAL" <<EOF
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

# Criar zona direta
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

# Criar zona reversa
cria_zona_reversa() {
    local zona_rev=$(echo $REDE | tr '.' '-')
    local ip_srv=$(hostname -I | awk '{print $1}')
    local ultimo_octeto=$(echo $ip_srv | awk -F. '{print $4}')
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
$ultimo_octeto       IN      PTR     $DOMINIO.
EOF
}

# Configurar named.conf.options
configura_named_conf_options() {
    IP_SERVIDOR=$(dialog --stdout --inputbox "Digite o IP do servidor DNS (ex: 192.168.0.1):" 8 50)
    [ -z "$IP_SERVIDOR" ] && return
    REDE_LOCAL=$(dialog --stdout --inputbox "Digite a rede local (ex: 192.168.0.0/24):" 8 50)
    [ -z "$REDE_LOCAL" ] && return

    sudo bash -c "cat > $CONF_OPTIONS" <<EOF
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
    sudo systemctl restart bind9
}

# Menu para editar resolv.conf
editar_resolv_conf() {
    while true; do
        OPCAO=$(dialog --stdout --menu "📝 Editar resolv.conf" 15 60 5 \
            1 "Adicionar entrada" \
            2 "Remover entrada" \
            0 "Voltar")

        case $OPCAO in
            1)
                DOM=$(dialog --stdout --inputbox "Informe o domínio (ex: grau.local):" 8 50)
                IP=$(dialog --stdout --inputbox "Informe o IP (ex: 192.168.0.1):" 8 50)
                echo "nameserver $IP" | sudo tee -a /etc/resolv.conf > /dev/null
                echo "search $DOM" | sudo tee -a /etc/resolv.conf > /dev/null
                dialog --msgbox "Entrada adicionada!" 6 40
                ;;
            2)
                TEMP="/tmp/resolv_temp"
                sudo cp /etc/resolv.conf $TEMP
                LINHAS=$(grep -nE "nameserver|search" $TEMP | awk -F: '{print $1 " " $2}')
                if [ -z "$LINHAS" ]; then
                    dialog --msgbox "Nenhuma entrada encontrada." 6 40
                else
                    ESCOLHA=$(echo "$LINHAS" | dialog --stdout --menu "Escolha linha para remover" 20 60 10)
                    if [ -n "$ESCOLHA" ]; then
                        sed -i "${ESCOLHA}d" $TEMP
                        sudo cp $TEMP /etc/resolv.conf
                        dialog --msgbox "Linha removida." 6 40
                    fi
                fi
                ;;
            0) return ;;
        esac
    done
}

# Configuração completa do DNS
configurar_dns() {
    while true; do
        OPCAO=$(dialog --stdout --menu "📡 Configuração DNS" 15 60 6 \
            1 "Configurar Zona Direta (atual: ${DOMINIO:-nenhuma})" \
            2 "Configurar Zona Reversa (atual: ${REDE:-nenhuma})" \
            3 "Configurar named.conf.options" \
            4 "Editar resolv.conf (Adicionar/Remover)" \
            5 "Aplicar configurações e reiniciar BIND" \
            0 "Voltar")

        case $OPCAO in
            1)
                DOM=$(dialog --stdout --inputbox "Informe o nome da zona direta (ex: grau.local):" 8 50 "$DOMINIO")
                [ -z "$DOM" ] && continue
                DOMINIO="$DOM"
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
                editar_resolv_conf
                ;;
            5)
                sudo systemctl restart bind9
                dialog --msgbox "Configurações aplicadas e BIND reiniciado!" 6 50
                ;;
            0)
                break
                ;;
        esac
    done
}

# Menu principal
while true; do
    OPCAO=$(dialog --stdout --menu "🛠️ Menu Principal" 15 60 5 \
        1 "Instalar DNS (BIND9)" \
        2 "Configurar DNS" \
        0 "Sair")

    case $OPCAO in
        1)
            instalar_bind9
            ;;
        2)
            configurar_dns
            ;;
        0)
            clear
            exit
            ;;
    esac
done
