#!/bin/bash

# Script DNS Interativo com dialog e configuração completa
# Versão com armazenamento de nameserver no formato "dominio ip"

# Verifica e instala dialog se necessário
if ! command -v dialog &>/dev/null; then
    apt-get update -qq
    apt-get install -y dialog >/dev/null 2>&1
fi

CONF_LOCAL="/etc/bind/named.conf.local"
CONF_OPTIONS="/etc/bind/named.conf.options"
DIR_ZONA="/etc/bind"

ARQ_DOMINIO="/tmp/dns_zona_direta.txt"
ARQ_REDE="/tmp/dns_zona_reversa.txt"
RESOLV_CUSTOM="/etc/resolv.conf.custom"

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
    local ult_oct=$(echo "$ip_srv" | awk -F. '{print $4}')
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
$ult_oct       IN      PTR     $DOMINIO.
EOF
}

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

configura_resolv_conf() {
    # Cria arquivo customizado se não existir
    [ ! -f "$RESOLV_CUSTOM" ] && sudo touch "$RESOLV_CUSTOM"

    while true; do
        RESOLV_OPC=$(dialog --stdout --menu "Gerenciar Nameservers" 12 50 3 \
            1 "Adicionar nameserver" \
            2 "Remover nameserver" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $RESOLV_OPC in
            1)
                NS_DOMINIO=$(dialog --stdout --inputbox "Digite o DOMÍNIO do nameserver (ex: grau.local):" 8 50)
                [ -z "$NS_DOMINIO" ] && continue
                
                NS_IP=$(dialog --stdout --inputbox "Digite o IP do nameserver (ex: 192.168.0.1):" 8 50)
                [ -z "$NS_IP" ] && continue

                # Adiciona no formato "dominio ip"
                echo "$NS_DOMINIO $NS_IP" | sudo tee -a "$RESOLV_CUSTOM" >/dev/null

                # Atualiza o resolv.conf oficial
                update_resolv_conf

                dialog --msgbox "Nameserver adicionado:\nDomínio: $NS_DOMINIO\nIP: $NS_IP" 8 50
                ;;
            2)
                # Lista nameservers existentes
                if [ ! -s "$RESOLV_CUSTOM" ]; then
                    dialog --msgbox "Nenhum nameserver configurado." 6 50
                    continue
                fi

                # Prepara menu de remoção
                OPTIONS=()
                i=1
                while read -r line; do
                    dominio=$(echo "$line" | awk '{print $1}')
                    ip=$(echo "$line" | awk '{print $2}')
                    OPTIONS+=("$i" "$dominio $ip")
                    ((i++))
                done < "$RESOLV_CUSTOM"

                SEL=$(dialog --stdout --menu "Escolha nameserver para remover:" 15 60 "${#OPTIONS[@]}" "${OPTIONS[@]}")
                [ -z "$SEL" ] && continue

                # Remove a linha selecionada
                sudo sed -i "${SEL}d" "$RESOLV_CUSTOM"
                update_resolv_conf

                dialog --msgbox "Nameserver removido com sucesso." 6 50
                ;;
            0) break ;;
        esac
    done
}

update_resolv_conf() {
    # Cria resolv.conf baseado no arquivo customizado
    sudo bash -c "echo '# Arquivo gerado automaticamente' > /etc/resolv.conf"
    while read -r line; do
        ip=$(echo "$line" | awk '{print $2}')
        sudo bash -c "echo 'nameserver $ip' >> /etc/resolv.conf"
    done < "$RESOLV_CUSTOM"
}

verifica_bind_instalado() {
    dpkg-query -W -f='${Status}' bind9 2>/dev/null | grep -q "install ok installed"
}

instalar_bind() {
    if verifica_bind_instalado; then
        dialog --msgbox "BIND9 já está instalado." 6 50
        return
    fi

    TMP_LOG="/tmp/bind_install.log"
    rm -f "$TMP_LOG"

    # Mostra barra de progresso real
    (
        echo "XXX"
        echo "Atualizando repositórios..."
        echo "XXX"
        apt-get update -qq >>"$TMP_LOG" 2>&1
        
        echo "XXX"
        echo "30"
        echo "Instalando BIND9..."
        echo "XXX"
        apt-get install -y --no-install-recommends bind9 bind9utils bind9-doc >>"$TMP_LOG" 2>&1
        
        echo "XXX"
        echo "100"
        echo "Instalação concluída!"
        echo "XXX"
        sleep 1
    ) | dialog --title "Instalando BIND9" --gauge "Preparando instalação..." 10 70 0

    if verifica_bind_instalado; then
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
        5 "Gerenciar Nameservers" \
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
