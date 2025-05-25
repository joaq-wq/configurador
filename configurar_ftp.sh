#!/bin/bash

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo "Execute este script como root ou com sudo."
    exit 1
fi

# Verificar dependência dialog
if ! command -v dialog &>/dev/null; then
    apt-get update && apt-get install -y dialog
fi

VSFTPD_CONF="/etc/vsftpd.conf"
CERT_DIR="/etc/ssl/certs"
KEY_DIR="/etc/ssl/private"

# ========== Função para instalar FTP ==========
instalar_ftp() {
    if dpkg -l | grep -qw vsftpd; then
        dialog --msgbox "✅ O vsftpd já está instalado." 6 50
        return
    fi

    (
        echo "10"; sleep 0.5
        echo "# Atualizando pacotes..."; apt update -y >/dev/null 2>&1
        echo "30"; sleep 0.5
        echo "# Instalando vsftpd..."; apt install -y vsftpd openssl >/dev/null 2>&1
        echo "80"; sleep 0.5
        echo "# Finalizando instalação..."
        sleep 1
        echo "100"
    ) | dialog --gauge "Instalando servidor FTP (vsftpd)..." 10 60 0

    dialog --msgbox "✅ vsftpd instalado com sucesso!" 6 50
}

# ========== Manipular Configurações ==========
set_config() {
    sed -i "/^$1=/d" "$VSFTPD_CONF"
    echo "$1=$2" >> "$VSFTPD_CONF"
}

get_config() {
    grep -E "^$1=" "$VSFTPD_CONF" | awk -F= '{print $2}'
}

# ========== Gerenciar Certificados ==========
gerenciar_certificados() {
    while true; do
        CERT_ATUAL=$(get_config "rsa_cert_file")
        KEY_ATUAL=$(get_config "rsa_private_key_file")
        SSL_STATUS=$(get_config "ssl_enable")

        OPCAO=$(dialog --stdout --menu "🔒 Gerenciar Certificados SSL\nAtivo: ${SSL_STATUS:-NO}" 20 70 10 \
            1 "Listar certificados existentes" \
            2 "Gerar novo certificado" \
            3 "Remover certificado atual" \
            4 "Ativar SSL/TLS" \
            5 "Desativar SSL/TLS" \
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
                rm -f "$CERT_ATUAL" "$KEY_ATUAL"
                set_config rsa_cert_file ""
                set_config rsa_private_key_file ""
                dialog --msgbox "🗑️ Certificado removido." 6 50
                ;;
            4)
                if [ -z "$CERT_ATUAL" ] || [ -z "$KEY_ATUAL" ]; then
                    dialog --msgbox "⚠️ Não há certificado configurado.\nCrie um primeiro." 7 60
                else
                    set_config ssl_enable YES
                    set_config allow_anon_ssl NO
                    set_config force_local_data_ssl YES
                    set_config force_local_logins_ssl YES
                    set_config ssl_tlsv1 YES
                    set_config ssl_sslv2 NO
                    set_config ssl_sslv3 NO
                    dialog --msgbox "🔒 SSL/TLS ativado." 6 50
                fi
                ;;
            5)
                set_config ssl_enable NO
                dialog --msgbox "🔓 SSL/TLS desativado." 6 50
                ;;
            0) break ;;
        esac
    done
}

# ========== Gerenciar Usuários ==========
gerenciar_usuarios() {
    while true; do
        OPCAO=$(dialog --stdout --menu "👥 Gerenciar Usuários FTP" 15 60 6 \
            1 "Listar usuários FTP" \
            2 "Adicionar usuário" \
            3 "Remover usuário" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1)
                cut -d: -f1 /etc/passwd | grep -v -E "root|daemon|bin|sys|sync|games|man|lp|mail|news|uucp|proxy|www-data|backup|list|irc|gnats|nobody|_apt|systemd.*|messagebus|syslog|ftp" > /tmp/users_list
                dialog --textbox /tmp/users_list 20 50
                ;;
            2)
                USER=$(dialog --stdout --inputbox "Digite o nome do usuário:" 8 40)
                [ -z "$USER" ] && continue

                PASS=$(dialog --stdout --insecure --passwordbox "Digite a senha do usuário:" 8 40)
                [ -z "$PASS" ] && continue

                useradd -m "$USER"
                echo "$USER:$PASS" | chpasswd

                dialog --msgbox "✅ Usuário $USER criado." 6 50
                ;;
            3)
                USER=$(dialog --stdout --inputbox "Digite o nome do usuário para remover:" 8 40)
                [ -z "$USER" ] && continue

                userdel -r "$USER"
                dialog --msgbox "🗑️ Usuário $USER removido." 6 50
                ;;
            0) break ;;
        esac
    done
}

# ========== Configurações Gerais ==========
configurar_ftp() {
    while true; do
        ANON=$(get_config "anonymous_enable")
        LOCAL=$(get_config "local_enable")
        WRITE=$(get_config "write_enable")
        CHROOT=$(get_config "chroot_local_user")
        SSL=$(get_config "ssl_enable")

        OPCAO=$(dialog --stdout --menu "⚙️ Configurações FTP" 20 70 10 \
            1 "Ativar/Desativar conexões anônimas (Atual: ${ANON:-NO})" \
            2 "Ativar/Desativar login de usuários locais (Atual: ${LOCAL:-NO})" \
            3 "Permitir/Desativar upload (Atual: ${WRITE:-NO})" \
            4 "Ativar/Desativar chroot (Atual: ${CHROOT:-NO})" \
            5 "Gerenciar SSL/TLS (Atual: ${SSL:-NO})" \
            6 "Gerenciar usuários FTP" \
            7 "Editar configuração manual (/etc/vsftpd.conf)" \
            8 "Reiniciar FTP" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1)
                dialog --yesno "Permitir conexões anônimas?" 7 50
                if [ $? -eq 0 ]; then
                    set_config anonymous_enable YES
                else
                    set_config anonymous_enable NO
                fi
                ;;
            2)
                STATUS=$(get_config "local_enable")
                if [ "$STATUS" == "YES" ]; then
                    set_config local_enable NO
                    dialog --msgbox "🚫 Login de usuários locais desativado." 6 50
                else
                    set_config local_enable YES
                    dialog --msgbox "✅ Login de usuários locais ativado." 6 50
                fi
                ;;
            3)
                dialog --yesno "Permitir upload e escrita?" 7 50
                if [ $? -eq 0 ]; then
                    set_config write_enable YES
                else
                    set_config write_enable NO
                fi
                ;;
            4)
                STATUS=$(get_config "chroot_local_user")
                if [ "$STATUS" == "YES" ]; then
                    set_config chroot_local_user NO
                    dialog --msgbox "🚫 Chroot desativado. Usuários podem navegar livremente." 6 60
                else
                    set_config chroot_local_user YES
                    dialog --msgbox "🔐 Chroot ativado. Usuários presos na pasta home." 6 60
                fi
                ;;
            5) gerenciar_certificados ;;
            6) gerenciar_usuarios ;;
            7) nano "$VSFTPD_CONF" ;;
            8)
                systemctl restart vsftpd
                dialog --msgbox "🔄 FTP reiniciado." 6 40
                ;;
            0) break ;;
        esac
    done
}

# ========== Menu Principal ==========
main_menu() {
    while true; do
        OPCAO=$(dialog --stdout --menu "🚀 Gerenciador vsftpd" 15 60 8 \
            1 "Instalar FTP (vsftpd)" \
            2 "Configurar FTP" \
            0 "Sair")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1) instalar_ftp ;;
            2) configurar_ftp ;;
            0) break ;;
        esac
    done
}

# Executa o menu principal
main_menu
