#!/bin/bash

# ===================== [ GERENCIADOR APACHE ] =====================

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo "⚠️ Execute este script como root ou com sudo."
    exit 1
fi

# Verificar dependência dialog
if ! command -v dialog &>/dev/null; then
    apt-get update && apt-get install -y dialog
fi

APACHE_CONF_DIR="/etc/apache2/sites-available"

# ===================== Função - Instalar Apache =====================
instalar_apache() {
    if dpkg -l | grep -qw apache2; then
        dialog --msgbox "✅ Apache já está instalado." 6 40
        return
    fi

    (
        for i in {1..100}; do
            if [ $i -eq 10 ]; then echo "# Atualizando pacotes..."; fi
            if [ $i -eq 40 ]; then echo "# Instalando Apache..."; fi
            if [ $i -eq 70 ]; then echo "# Finalizando instalação..."; fi
            sleep 0.03
            echo $i
        done | dialog --gauge "🔧 Instalando servidor Apache..." 10 70 0
        apt update -y >/dev/null 2>&1
        apt install -y apache2 >/dev/null 2>&1
    )

    dialog --msgbox "✅ Apache instalado com sucesso!" 6 50
}

# ===================== Função - Criar Virtual Host =====================
criar_virtualhost() {
    DOMINIO=$(dialog --stdout --inputbox "🔤 Digite o domínio (ex: meusite.com):" 8 50)
    [ -z "$DOMINIO" ] && return

    DIR="/var/www/$DOMINIO"
    CONF_FILE="$APACHE_CONF_DIR/$DOMINIO.conf"

    mkdir -p "$DIR"
    echo "<h1>Site $DOMINIO funcionando!</h1>" > "$DIR/index.html"

    cat > "$CONF_FILE" <<EOF
<VirtualHost *:80>
    ServerName $DOMINIO
    ServerAlias www.$DOMINIO

    DocumentRoot $DIR

    <Directory $DIR>
        Options -Indexes +FollowSymLinks
        AllowOverride All
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/$DOMINIO-error.log
    CustomLog \${APACHE_LOG_DIR}/$DOMINIO-access.log combined
</VirtualHost>
EOF

    a2ensite "$DOMINIO.conf" >/dev/null 2>&1

    # Adicionar no /etc/hosts
    grep -qxF "127.0.0.1 $DOMINIO www.$DOMINIO" /etc/hosts || echo "127.0.0.1 $DOMINIO www.$DOMINIO" >> /etc/hosts

    systemctl reload apache2

    dialog --msgbox "✅ Domínio $DOMINIO criado e ativado!\nAcesse: http://$DOMINIO" 8 60
}

# ===================== Função - Listar Virtual Hosts =====================
listar_virtualhosts() {
    VHOSTS=$(ls $APACHE_CONF_DIR | grep .conf | sed 's/.conf//')
    echo "$VHOSTS" > /tmp/vhosts_list
    dialog --textbox /tmp/vhosts_list 20 50
}

# ===================== Função - Remover Virtual Host =====================
remover_virtualhost() {
    DOMINIO=$(dialog --stdout --inputbox "Digite o domínio a remover:" 8 50)
    [ -z "$DOMINIO" ] && return

    a2dissite "$DOMINIO.conf" >/dev/null 2>&1
    rm -f "$APACHE_CONF_DIR/$DOMINIO.conf"
    rm -rf "/var/www/$DOMINIO"
    sed -i "/$DOMINIO/d" /etc/hosts

    systemctl reload apache2

    dialog --msgbox "🗑️ Domínio $DOMINIO removido com sucesso." 7 50
}

# ===================== Função - Gerenciar Virtual Hosts =====================
gerenciar_virtualhost() {
    while true; do
        OPCAO=$(dialog --stdout --menu "🌐 Gerenciar Virtual Hosts" 15 60 5 \
            1 "Criar novo Virtual Host" \
            2 "Listar Virtual Hosts" \
            3 "Remover Virtual Host" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1) criar_virtualhost ;;
            2) listar_virtualhosts ;;
            3) remover_virtualhost ;;
            0) break ;;
        esac
    done
}

# ===================== Função - Configurações Gerais =====================
configuracoes_apache() {
    while true; do
        OPCAO=$(dialog --stdout --menu "⚙️ Configurações do Apache" 15 60 5 \
            1 "Editar arquivo principal (/etc/apache2/apache2.conf)" \
            2 "Editar arquivo ports.conf" \
            3 "Reiniciar Apache" \
            4 "Verificar Status" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1) nano /etc/apache2/apache2.conf ;;
            2) nano /etc/apache2/ports.conf ;;
            3)
                systemctl restart apache2
                dialog --msgbox "🔄 Apache reiniciado." 6 40
                ;;
            4)
                systemctl status apache2 | tee /tmp/apache_status
                dialog --textbox /tmp/apache_status 20 70
                ;;
            0) break ;;
        esac
    done
}

# ===================== Menu Principal =====================
menu_principal() {
    while true; do
        OPCAO=$(dialog --stdout --menu "🚀 Gerenciador Apache" 15 60 6 \
            1 "Instalar Apache" \
            2 "Gerenciar Virtual Hosts" \
            3 "Configurações Gerais" \
            0 "Sair")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1) instalar_apache ;;
            2) gerenciar_virtualhost ;;
            3) configuracoes_apache ;;
            0) break ;;
        esac
    done
}

# ===================== Executa o Menu =====================
menu_principal
