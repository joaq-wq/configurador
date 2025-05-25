#!/bin/bash

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo "Execute este script como root ou com sudo."
    exit 1
fi

# Verificar dependência dialog
if ! command -v dialog &>/dev/null; then
    apt update && apt install -y dialog
fi

APACHE_CONF_DIR="/etc/apache2"
SITES_AVAILABLE="$APACHE_CONF_DIR/sites-available"
SITES_ENABLED="$APACHE_CONF_DIR/sites-enabled"
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"

# ========= Instalar Apache =========
instalar_apache() {
    if dpkg -l | grep -qw apache2; then
        dialog --msgbox "✅ Apache já está instalado." 6 50
        return
    fi

    (
        echo "10"; sleep 0.5
        echo "# Atualizando pacotes..."; apt update -y >/dev/null 2>&1
        echo "40"; sleep 0.5
        echo "# Instalando Apache..."; apt install -y apache2 openssl >/dev/null 2>&1
        echo "90"; sleep 0.5
        echo "# Finalizando instalação..."
        sleep 1
        echo "100"
    ) | dialog --gauge "Instalando servidor Apache..." 10 60 0

    dialog --msgbox "✅ Apache instalado com sucesso!" 6 50
}

# ========= Gerenciar Certificados SSL =========
gerenciar_ssl() {
    while true; do
        OPCAO=$(dialog --stdout --menu "🔒 Gerenciar SSL/TLS" 15 60 6 \
            1 "Listar certificados" \
            2 "Gerar novo certificado" \
            3 "Remover certificado" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1)
                ls $CERT_DIR/*.pem 2>/dev/null > /tmp/certs_list || echo "Nenhum certificado encontrado" > /tmp/certs_list
                dialog --textbox /tmp/certs_list 20 70
                ;;
            2)
                NOME=$(dialog --stdout --inputbox "Nome do certificado (sem espaço):" 8 40)
                [ -z "$NOME" ] && continue

                openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
                    -keyout "$KEY_DIR/$NOME-key.pem" \
                    -out "$CERT_DIR/$NOME-cert.pem" \
                    -subj "/C=BR/ST=Estado/L=Cidade/O=Empresa/OU=TI/CN=$(hostname)"

                dialog --msgbox "✅ Certificado criado:\n$CERT_DIR/$NOME-cert.pem" 8 60
                ;;
            3)
                NOME=$(dialog --stdout --inputbox "Nome do certificado para remover (sem extensão .pem):" 8 50)
                [ -z "$NOME" ] && continue

                rm -f "$CERT_DIR/$NOME-cert.pem" "$KEY_DIR/$NOME-key.pem"
                dialog --msgbox "🗑️ Certificado $NOME removido." 6 50
                ;;
            0) break ;;
        esac
    done
}

# ========= Gerenciar Sites =========
gerenciar_sites() {
    while true; do
        OPCAO=$(dialog --stdout --menu "🌐 Gerenciar Sites (Virtual Hosts)" 20 70 10 \
            1 "Listar sites disponíveis" \
            2 "Ativar site" \
            3 "Desativar site" \
            4 "Criar novo site" \
            5 "Remover site" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1)
                ls "$SITES_AVAILABLE" > /tmp/sites_list
                dialog --textbox /tmp/sites_list 20 60
                ;;
            2)
                SITE=$(dialog --stdout --inputbox "Nome do site (arquivo .conf):" 8 50)
                [ -z "$SITE" ] && continue

                a2ensite "$SITE"
                systemctl reload apache2
                dialog --msgbox "✅ Site $SITE ativado." 6 50
                ;;
            3)
                SITE=$(dialog --stdout --inputbox "Nome do site (arquivo .conf):" 8 50)
                [ -z "$SITE" ] && continue

                a2dissite "$SITE"
                systemctl reload apache2
                dialog --msgbox "🛑 Site $SITE desativado." 6 50
                ;;
            4)
                NOME=$(dialog --stdout --inputbox "Nome do site (sem espaços):" 8 40)
                [ -z "$NOME" ] && continue

                DOMINIO=$(dialog --stdout --inputbox "Domínio (ex.: site.com):" 8 40)
                [ -z "$DOMINIO" ] && continue

                DIR="/var/www/$NOME"
                mkdir -p "$DIR"
                chown -R www-data:www-data "$DIR"

                cat <<EOF >"$SITES_AVAILABLE/$NOME.conf"
<VirtualHost *:80>
    ServerName $DOMINIO
    DocumentRoot $DIR
    ErrorLog \${APACHE_LOG_DIR}/$NOME-error.log
    CustomLog \${APACHE_LOG_DIR}/$NOME-access.log combined
</VirtualHost>
EOF

                dialog --msgbox "✅ Site $NOME criado em $DIR.\nEdite se necessário." 8 60
                nano "$SITES_AVAILABLE/$NOME.conf"
                a2ensite "$NOME.conf"
                systemctl reload apache2
                ;;
            5)
                SITE=$(dialog --stdout --inputbox "Nome do site (arquivo .conf):" 8 50)
                [ -z "$SITE" ] && continue

                a2dissite "$SITE"
                rm -f "$SITES_AVAILABLE/$SITE"
                dialog --msgbox "🗑️ Site $SITE removido." 6 50
                systemctl reload apache2
                ;;
            0) break ;;
        esac
    done
}

# ========= Gerenciar Módulos =========
gerenciar_modulos() {
    while true; do
        OPCAO=$(dialog --stdout --menu "🔌 Gerenciar Módulos do Apache" 15 60 6 \
            1 "Listar módulos ativos" \
            2 "Ativar módulo" \
            3 "Desativar módulo" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1)
                apache2ctl -M | tee /tmp/modulos_list
                dialog --textbox /tmp/modulos_list 20 70
                ;;
            2)
                MOD=$(dialog --stdout --inputbox "Nome do módulo (sem .so):" 8 40)
                [ -z "$MOD" ] && continue

                a2enmod "$MOD"
                systemctl reload apache2
                dialog --msgbox "✅ Módulo $MOD ativado." 6 50
                ;;
            3)
                MOD=$(dialog --stdout --inputbox "Nome do módulo (sem .so):" 8 40)
                [ -z "$MOD" ] && continue

                a2dismod "$MOD"
                systemctl reload apache2
                dialog --msgbox "🛑 Módulo $MOD desativado." 6 50
                ;;
            0) break ;;
        esac
    done
}

# ========= Gerenciar Serviço =========
gerenciar_servico() {
    while true; do
        OPCAO=$(dialog --stdout --menu "🛠️ Gerenciar Serviço Apache" 15 60 6 \
            1 "Status" \
            2 "Reiniciar" \
            3 "Parar" \
            4 "Iniciar" \
            5 "Ativar na inicialização" \
            6 "Desativar na inicialização" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1) systemctl status apache2 | tee /tmp/status_apache
               dialog --textbox /tmp/status_apache 20 70
               ;;
            2) systemctl restart apache2
               dialog --msgbox "🔄 Apache reiniciado." 6 40 ;;
            3) systemctl stop apache2
               dialog --msgbox "🛑 Apache parado." 6 40 ;;
            4) systemctl start apache2
               dialog --msgbox "▶️ Apache iniciado." 6 40 ;;
            5) systemctl enable apache2
               dialog --msgbox "🔒 Apache ativado na inicialização." 6 50 ;;
            6) systemctl disable apache2
               dialog --msgbox "🔓 Apache desativado na inicialização." 6 50 ;;
            0) break ;;
        esac
    done
}

# ========= Configurações Gerais =========
configuracoes_apache() {
    while true; do
        OPCAO=$(dialog --stdout --menu "⚙️ Configurações Gerais Apache" 20 70 10 \
            1 "Gerenciar Sites (Virtual Hosts)" \
            2 "Gerenciar SSL/TLS" \
            3 "Gerenciar Módulos" \
            4 "Editar apache2.conf manualmente" \
            5 "Editar ports.conf (Portas)" \
            6 "Gerenciar Serviço Apache" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1) gerenciar_sites ;;
            2) gerenciar_ssl ;;
            3) gerenciar_modulos ;;
            4) nano "$APACHE_CONF_DIR/apache2.conf" ;;
            5) nano "$APACHE_CONF_DIR/ports.conf" ;;
            6) gerenciar_servico ;;
            0) break ;;
        esac
    done
}

# ========= Menu Principal =========
main_menu() {
    while true; do
        OPCAO=$(dialog --stdout --menu "🚀 Gerenciador Apache" 15 60 8 \
            1 "Instalar Apache" \
            2 "Configurar Apache" \
            0 "Sair")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1) instalar_apache ;;
            2) configuracoes_apache ;;
            0) break ;;
        esac
    done
}

main_menu
