#!/bin/bash

# =============================
# Script Master de DNS - by Joaquimkj
# =============================

# Verifica se está rodando como root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Este script precisa ser executado como root."
    exit 1
fi

# Verifica e instala o dialog com barra de progresso
if ! command -v dialog &> /dev/null; then
    (
    echo 20; echo "🔄 Atualizando pacotes..."; sleep 1
    apt update -y &>/dev/null
    echo 60; echo "⬇️ Instalando Dialog..."; sleep 1
    apt install -y dialog &>/dev/null
    echo 100; echo "✅ Concluído..."; sleep 1
    ) | dialog --gauge "⏳ Instalando dependências..." 10 60 0
fi

# Instala Bind9 se não tiver
if ! dpkg -l | grep -q bind9; then
    (
    echo 20; echo "🔄 Atualizando pacotes..."; sleep 1
    apt update -y &>/dev/null
    echo 60; echo "⬇️ Instalando Bind9..."; sleep 1
    apt install -y bind9 bind9utils bind9-doc &>/dev/null
    echo 100; echo "✅ Concluído..."; sleep 1
    ) | dialog --gauge "⏳ Instalando o servidor DNS (Bind9)..." 10 60 0
fi

# Caminhos dos arquivos
CONF_LOCAL="/etc/bind/named.conf.local"
DIR_ZONA="/etc/bind"

# Função principal
configurar_dns() {

    # Coleta domínio da zona direta
    DOMINIO=$(dialog --stdout --inputbox "Digite o nome da Zona Direta (ex: empresa.com):" 8 50)
    [ -z "$DOMINIO" ] && exit

    # Coleta IP da zona reversa
    REDE=$(dialog --stdout --inputbox "Digite o IP da rede para a Zona Reversa (ex: 192.168.1):" 8 50)
    [ -z "$REDE" ] && exit

    ZONA_REVERSE=$(echo $REDE | awk -F. '{print $3"."$2"."$1".in-addr.arpa"}')

    # Arquivos de zona
    ZONA_DIR="$DIR_ZONA/db.$DOMINIO"
    ZONA_REV="$DIR_ZONA/db.$(echo $REDE | tr '.' '-')"

    # Backup dos arquivos
    cp $CONF_LOCAL $CONF_LOCAL.bkp.$(date +%s)

    # Adiciona as zonas no named.conf.local
    echo "zone \"$DOMINIO\" {
    type master;
    file \"$ZONA_DIR\";
};" >> $CONF_LOCAL

    echo "zone \"$ZONA_REVERSE\" {
    type master;
    file \"$ZONA_REV\";
};" >> $CONF_LOCAL

    # Cria arquivo da zona direta
    cat <<EOF > $ZONA_DIR
\$TTL    604800
@       IN      SOA     ns.$DOMINIO. root.$DOMINIO. (
                             $(date +%Y%m%d)01 ; Serial
                        604800         ; Refresh
                         86400         ; Retry
                       2419200         ; Expire
                        604800 )       ; Negative Cache TTL
;
@       IN      NS      ns.$DOMINIO.
ns      IN      A       $(hostname -I | awk '{print $1}')
EOF

    # Cria arquivo da zona reversa
    cat <<EOF > $ZONA_REV
\$TTL    604800
@       IN      SOA     ns.$DOMINIO. root.$DOMINIO. (
                             $(date +%Y%m%d)01 ; Serial
                        604800         ; Refresh
                         86400         ; Retry
                       2419200         ; Expire
                        604800 )       ; Negative Cache TTL
;
@       IN      NS      ns.$DOMINIO.
EOF

    # Loop para adicionar registros
    while true; do
        OPCAO=$(dialog --stdout --menu "🗂️ Adicione registros DNS para $DOMINIO" 15 60 6 \
        1 "Adicionar Registro A" \
        2 "Adicionar CNAME (Alias)" \
        3 "Adicionar MX (E-mail)" \
        4 "Finalizar e aplicar" \
        0 "Sair sem aplicar")

        case $OPCAO in
            1)
                HOST=$(dialog --stdout --inputbox "Digite o nome do host (ex: www, ftp, apache):" 8 50)
                IP=$(dialog --stdout --inputbox "Digite o IP desse host:" 8 50)
                echo "$HOST    IN      A       $IP" >> $ZONA_DIR

                # Adiciona na zona reversa
                ULT_OCT=$(echo $IP | awk -F. '{print $4}')
                echo "$ULT_OCT    IN      PTR     $HOST.$DOMINIO." >> $ZONA_REV
                ;;

            2)
                ALIAS=$(dialog --stdout --inputbox "Digite o nome do Alias (ex: app):" 8 50)
                ALVO=$(dialog --stdout --inputbox "Para qual host ele aponta? (ex: www):" 8 50)
                echo "$ALIAS    IN      CNAME    $ALVO.$DOMINIO." >> $ZONA_DIR
                ;;

            3)
                MXHOST=$(dialog --stdout --inputbox "Digite o hostname do servidor de e-mail (ex: mail):" 8 50)
                PRIORIDADE=$(dialog --stdout --inputbox "Digite a prioridade do MX (ex: 10):" 8 50)
                echo "@    IN      MX      $PRIORIDADE    $MXHOST.$DOMINIO." >> $ZONA_DIR
                ;;

            4)
                break
                ;;

            0)
                dialog --msgbox "❌ Cancelado. Nenhuma alteração aplicada." 6 50
                exit
                ;;
        esac
    done

    # Verifica sintaxe
    named-checkconf
    named-checkzone $DOMINIO $ZONA_DIR
    named-checkzone $ZONA_REVERSE $ZONA_REV

    # Reinicia serviço
    systemctl restart bind9

    dialog --msgbox "✅ DNS Configurado para $DOMINIO e serviço BIND9 reiniciado com sucesso!" 7 60
}

# Executa função
configurar_dns

clear
echo "✅ Script DNS finalizado com sucesso!"
