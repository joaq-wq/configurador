#!/bin/bash

# Script DNS Interativo Completo v4.0
# Melhorias: Barra de progresso funcional, gerenciamento de registros DNS completo, correções de sintaxe

# Verifica e instala dialog se necessário
if ! command -v dialog &>/dev/null; then
    apt-get update -qq
    apt-get install -y dialog >/dev/null 2>&1
fi

# Configurações
CONF_LOCAL="/etc/bind/named.conf.local"
CONF_OPTIONS="/etc/bind/named.conf.options"
DIR_ZONA="/etc/bind"
ARQ_DOMINIO="/tmp/dns_zona_direta.txt"
ARQ_REDE="/tmp/dns_zona_reversa.txt"
RESOLV_CUSTOM="/etc/resolv.conf.custom"

DOMINIO=$( [ -f "$ARQ_DOMINIO" ] && cat "$ARQ_DOMINIO" || echo "" )
REDE=$( [ -f "$ARQ_REDE" ] && cat "$ARQ_REDE" || echo "" )

# Funções
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
                              $(date +%Y%m%d)01 ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$DOMINIO.
@       IN      A       $ip_srv
ns1     IN      A       $ip_srv
EOF
}

cria_zona_reversa() {
    local zona_rev=$(echo $REDE | tr '.' '-')
    local ip_srv=$(hostname -I | awk '{print $1}')
    local ult_oct=$(echo "$ip_srv" | awk -F. '{print $4}')
    sudo bash -c "cat > $DIR_ZONA/db.$zona_rev" <<EOF
\$TTL    604800
@       IN      SOA     $DOMINIO. root.$DOMINIO. (
                              $(date +%Y%m%d)01 ; Serial
                         604800         ; Refresh
                          86400         ; Retry
                        2419200         ; Expire
                         604800 )       ; Negative Cache TTL
;
@       IN      NS      ns1.$DOMINIO.
$ult_oct       IN      PTR     ns1.$DOMINIO.
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

gerenciar_registros_dns() {
    while true; do
        OPCAO=$(dialog --stdout --menu "📝 Gerenciar Registros DNS para $DOMINIO" 17 60 7 \
            1 "Adicionar registro A (IPv4)" \
            2 "Adicionar registro CNAME (Alias)" \
            3 "Adicionar registro MX (Mail Exchange)" \
            4 "Adicionar registro customizado" \
            5 "Listar registros existentes" \
            6 "Remover registro" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1)
                NOME=$(dialog --stdout --inputbox "Nome do host (ex: www, mail, @ para domínio):" 8 50)
                [ -z "$NOME" ] && continue
                IP=$(dialog --stdout --inputbox "Endereço IPv4 para $NOME:" 8 50)
                [ -z "$IP" ] && continue
                sudo bash -c "echo '$NOME     IN      A       $IP' >> $DIR_ZONA/db.$DOMINIO"
                dialog --msgbox "Registro A adicionado:\n$NOME.$DOMINIO → $IP" 8 50
                ;;
            2)
                ALIAS=$(dialog --stdout --inputbox "Nome do alias (ex: www, ftp):" 8 50)
                [ -z "$ALIAS" ] && continue
                REAL=$(dialog --stdout --inputbox "Nome real do host (ex: server1, @ para domínio):" 8 50)
                [ -z "$REAL" ] && continue
                sudo bash -c "echo '$ALIAS     IN      CNAME       $REAL' >> $DIR_ZONA/db.$DOMINIO"
                dialog --msgbox "Registro CNAME adicionado:\n$ALIAS.$DOMINIO → $REAL.$DOMINIO" 8 50
                ;;
            3)
                PRIORIDADE=$(dialog --stdout --inputbox "Prioridade MX (ex: 10):" 8 50)
                [ -z "$PRIORIDADE" ] && continue
                SERVIDOR=$(dialog --stdout --inputbox "FQDN do servidor de email:" 8 50)
                [ -z "$SERVIDOR" ] && continue
                sudo bash -c "echo '@     IN      MX       $PRIORIDADE      $SERVIDOR.' >> $DIR_ZONA/db.$DOMINIO"
                dialog --msgbox "Registro MX adicionado:\n@.$DOMINIO → $SERVIDOR (Prioridade: $PRIORIDADE)" 8 50
                ;;
            4)
                REGISTRO=$(dialog --stdout --inputbox "Registro customizado (formato BIND):" 12 60 "nome IN TTL tipo valor")
                [ -z "$REGISTRO" ] && continue
                sudo bash -c "echo '$REGISTRO' >> $DIR_ZONA/db.$DOMINIO"
                dialog --msgbox "Registro adicionado:\n$REGISTRO" 8 60
                ;;
            5)
                clear
                echo "=== Registros DNS para $DOMINIO ==="
                echo "----------------------------------"
                grep -vE '^\$|^;' "$DIR_ZONA/db.$DOMINIO" | awk '{print $1,$3,$4,$5}' | column -t
                echo "----------------------------------"
                read -p "Pressione Enter para continuar..."
                ;;
            6)
                LISTA_REGISTROS=$(grep -vE '^\$|^;' "$DIR_ZONA/db.$DOMINIO" | nl -ba -w 2 -s ') ')
                if [ -z "$LISTA_REGISTROS" ]; then
                    dialog --msgbox "Nenhum registro encontrado para remoção." 6 50
                    continue
                fi

                SELECAO=$(dialog --stdout --menu "Selecione o registro para remover:" 20 70 13 $LISTA_REGISTROS)
                [ -z "$SELECAO" ] && continue

                sudo sed -i "${SELECAO}d" "$DIR_ZONA/db.$DOMINIO"
                dialog --msgbox "Registro removido com sucesso." 6 50
                ;;
            0) break ;;
        esac
        
        # Incrementa serial após modificações
        if [[ $OPCAO -ge 1 && $OPCAO -le 4 ]] || [[ $OPCAO -eq 6 ]]; then
            DATA=$(date +%Y%m%d%H)
            sudo sed -i "s/^\(\s*[0-9]\+\s*;\s*Serial\)/${DATA}00 ; Serial/" "$DIR_ZONA/db.$DOMINIO"
            sudo systemctl reload bind9
        fi
    done
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

    # Barra de progresso real
    (
        echo "XXX"
        echo "0"
        echo "Preparando instalação..."
        echo "XXX"
        DEBIAN_FRONTEND=noninteractive apt-get update -qq >>"$TMP_LOG" 2>&1
        
        echo "XXX"
        echo "30"
        echo "Instalando BIND9..."
        echo "XXX"
        DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
            bind9 bind9utils bind9-doc >>"$TMP_LOG" 2>&1
        
        echo "XXX"
        echo "100"
        echo "Instalação concluída!"
        echo "XXX"
        sleep 1
    ) | dialog --title "Instalando BIND9" --gauge "Por favor aguarde..." 10 70 0

    if verifica_bind_instalado; then
        dialog --msgbox "BIND9 instalado com sucesso!" 6 50
    else
        dialog --msgbox "Erro na instalação. Veja $TMP_LOG" 8 60
        exit 1
    fi
}

# Menu principal
while true; do
    DOMINIO_ATUAL=${DOMINIO:-"nenhuma"}
    REDE_ATUAL=${REDE:-"nenhuma"}

    OPCAO=$(dialog --stdout --menu "📡 Configuração DNS" 17 60 7 \
        1 "Instalar BIND9" \
        2 "Configurar Zona Direta (atual: $DOMINIO_ATUAL)" \
        3 "Configurar Zona Reversa (atual: $REDE_ATUAL)" \
        4 "Configurar named.conf.options" \
        5 "Gerenciar /etc/resolv.conf" \
        6 "Gerenciar Registros DNS" \
        0 "Sair")

    [ $? -ne 0 ] && break

    case $OPCAO in
        1) instalar_bind ;;
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
        4) configura_named_conf_options ;;
        5) configura_resolv_conf ;;
        6)
            [ -z "$DOMINIO" ] && { dialog --msgbox "Configure primeiro a zona direta!" 6 50; continue; }
            gerenciar_registros_dns
            ;;
        0)
            clear
            exit 0
            ;;
    esac
done
