#!/bin/bash

CONFIG_FILE="/etc/vsftpd.conf"
USUARIOS_FILE="/etc/ftp_users.txt"

# --- Funções básicas para leitura e escrita da config ---

check_config() {
    local chave="$1"
    grep -E "^$chave=" "$CONFIG_FILE" | tail -1 | cut -d= -f2
}

set_config() {
    local chave="$1"
    local valor="$2"
    if grep -qE "^$chave=" "$CONFIG_FILE"; then
        sed -i "s|^$chave=.*|$chave=$valor|" "$CONFIG_FILE"
    else
        echo "$chave=$valor" >> "$CONFIG_FILE"
    fi
}

editar_configuracao() {
    nano "$CONFIG_FILE"
}

# --- SSL ---

listar_certificados_ssl() {
    dialog --msgbox "Certificados SSL encontrados:\n\n$(ls -l /etc/ssl/certs/*.pem 2>/dev/null)" 15 60
}

remover_certificados_ssl() {
    CERT=$(dialog --stdout --inputbox "Digite o caminho completo do certificado para remover:" 8 60 "/etc/ssl/certs/ftp-cert.pem")
    KEY=$(dialog --stdout --inputbox "Digite o caminho completo da chave privada para remover:" 8 60 "/etc/ssl/private/ftp-key.pem")
    
    if [ -f "$CERT" ] && [ -f "$KEY" ]; then
        rm -f "$CERT" "$KEY"
        dialog --msgbox "Certificado e chave removidos." 6 40
    else
        dialog --msgbox "Arquivo(s) não encontrado(s)." 6 40
    fi
}

adicionar_certificado_ssl() {
    DIR_CERT="/etc/ssl/certs"
    DIR_KEY="/etc/ssl/private"

    CERT_PATH=$(dialog --stdout --inputbox "Caminho para salvar certificado (.pem):" 8 60 "${DIR_CERT}/ftp-cert.pem")
    KEY_PATH=$(dialog --stdout --inputbox "Caminho para salvar chave privada (.pem):" 8 60 "${DIR_KEY}/ftp-key.pem")

    if [ -z "$CERT_PATH" ] || [ -z "$KEY_PATH" ]; then
        dialog --msgbox "Caminho inválido." 6 40
        return
    fi

    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$KEY_PATH" \
        -out "$CERT_PATH" \
        -subj "/C=BR/ST=Estado/L=Cidade/O=MinhaEmpresa/OU=TI/CN=$(hostname)"

    dialog --msgbox "✅ Certificado gerado:\n$CERT_PATH\n$KEY_PATH" 8 60
}

alternar_ssl() {
    SSL_STATUS=$(check_config "ssl_enable")
    if [ "$SSL_STATUS" == "YES" ]; then
        dialog --yesno "TLS/SSL está ativado. Deseja desativar?" 7 50
        if [ $? -eq 0 ]; then
            set_config ssl_enable NO
            dialog --msgbox "🔓 TLS/SSL desativado." 6 40
        fi
    else
        dialog --yesno "TLS/SSL está desativado. Deseja ativar?" 7 50
        if [ $? -eq 0 ]; then
            CERT_PATH=$(dialog --stdout --inputbox "Caminho do certificado (.pem):" 8 60 "/etc/ssl/certs/ftp-cert.pem")
            KEY_PATH=$(dialog --stdout --inputbox "Caminho da chave privada (.pem):" 8 60 "/etc/ssl/private/ftp-key.pem")

            if [ ! -f "$CERT_PATH" ] || [ ! -f "$KEY_PATH" ]; then
                dialog --msgbox "Certificado ou chave não encontrado." 6 40
                return
            fi

            set_config ssl_enable YES
            set_config rsa_cert_file "$CERT_PATH"
            set_config rsa_private_key_file "$KEY_PATH"
            set_config allow_anon_ssl NO
            set_config force_local_data_ssl YES
            set_config force_local_logins_ssl YES
            set_config ssl_tlsv1 YES
            set_config ssl_sslv2 NO
            set_config ssl_sslv3 NO

            dialog --msgbox "🔒 TLS/SSL ativado com certificado:\n$CERT_PATH" 8 60
        fi
    fi
}

menu_ssl() {
    while true; do
        OP_SSL=$(dialog --stdout --menu "Gerenciar SSL/TLS" 15 60 6 \
            1 "Listar certificados SSL" \
            2 "Adicionar novo certificado" \
            3 "Remover certificado" \
            4 "Ativar/Desativar SSL" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $OP_SSL in
            1) listar_certificados_ssl ;;
            2) adicionar_certificado_ssl ;;
            3) remover_certificados_ssl ;;
            4) alternar_ssl ;;
            0) break ;;
        esac
    done
}

# --- Login local ---

toggle_login_local() {
    STATUS=$(check_config "local_enable")
    if [ "$STATUS" == "YES" ]; then
        dialog --yesno "Login de usuários locais está ativado. Deseja desativar?" 7 50
        if [ $? -eq 0 ]; then
            set_config local_enable NO
            dialog --msgbox "Login local desativado." 6 40
        fi
    else
        dialog --yesno "Login de usuários locais está desativado. Deseja ativar?" 7 50
        if [ $? -eq 0 ]; then
            set_config local_enable YES
            dialog --msgbox "Login local ativado." 6 40
        fi
    fi
}

# --- Chroot ---

toggle_chroot() {
    STATUS=$(check_config "chroot_local_user")
    if [ "$STATUS" == "YES" ]; then
        dialog --yesno "Chroot está ativado. Deseja desativar?" 7 50
        if [ $? -eq 0 ]; then
            set_config chroot_local_user NO
            dialog --msgbox "Chroot desativado." 6 40
        fi
    else
        dialog --yesno "Chroot está desativado. Deseja ativar?" 7 50
        if [ $? -eq 0 ]; then
            set_config chroot_local_user YES
            dialog --msgbox "Chroot ativado." 6 40
        fi
    fi
}

# --- Gerenciar usuários FTP ---

criar_usuario() {
    USER=$(dialog --stdout --inputbox "Digite o nome do usuário:" 8 40)
    [ -z "$USER" ] && return

    PASS=$(dialog --stdout --insecure --passwordbox "Digite a senha do usuário:" 8 40)
    [ -z "$PASS" ] && return

    if id "$USER" &>/dev/null; then
        dialog --msgbox "Usuário já existe." 6 40
        return
    fi

    useradd -m "$USER"
    echo "$USER:$PASS" | chpasswd
    # Cria a pasta home com permissão segura
    chmod 700 /home/"$USER"

    # Registra no arquivo de controle
    if ! grep -q "^$USER$" "$USUARIOS_FILE" 2>/dev/null; then
        echo "$USER" >> "$USUARIOS_FILE"
    fi

    dialog --msgbox "✅ Usuário $USER criado com sucesso!" 6 50
}

listar_usuarios() {
    if [ ! -f "$USUARIOS_FILE" ] || [ ! -s "$USUARIOS_FILE" ]; then
        dialog --msgbox "Nenhum usuário FTP criado via script." 6 50
        return
    fi

    USUARIOS=$(cat "$USUARIOS_FILE" | tr '\n' ' ')
    SELECIONE=$(dialog --stdout --menu "Usuários FTP criados:" 15 50 10 $(for u in $USUARIOS; do echo "$u" "$u"; done))

    if [ -z "$SELECIONE" ]; then
        return
    fi

    dialog --yesno "Deseja remover o usuário '$SELECIONE'?" 7 50
    if [ $? -eq 0 ]; then
        userdel -r "$SELECIONE"
        sed -i "/^$SELECIONE$/d" "$USUARIOS_FILE"
        dialog --msgbox "Usuário '$SELECIONE' removido." 6 40
    fi
}

# --- Menu principal de configuração FTP ---

configurar_ftp() {
    while true; do
        ANON=$(check_config "anonymous_enable")
        LOCAL=$(check_config "local_enable")
        WRITE=$(check_config "write_enable")
        CHROOT=$(check_config "chroot_local_user")
        SSL=$(check_config "ssl_enable")

        SUB_OPCAO=$(dialog --stdout --menu "⚙️ Configurar FTP" 20 70 15 \
            1 "Permitir conexões anônimas (Atual: ${ANON:-NO})" \
            2 "Ativar/Desativar login de usuários locais (Atual: ${LOCAL:-NO})" \
            3 "Permitir upload (Atual: ${WRITE:-NO})" \
            4 "Ativar/Desativar chroot (Atual: ${CHROOT:-NO})" \
            5 "Configurar TLS/SSL (Atual: ${SSL:-NO})" \
            6 "Gerenciar usuários FTP" \
            7 "Editar configuração manual (nano)" \
            8 "Reiniciar FTP" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $SUB_OPCAO in
            1)
                dialog --yesno "Permitir conexões anônimas?" 7 50
                if [ $? -eq 0 ]; then
                    set_config anonymous_enable YES
                else
                    set_config anonymous_enable NO
                fi
                ;;
            2)
                toggle_login_local
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
                toggle_chroot
                ;;
            5)
                menu_ssl
                ;;
            6)
                while true; do
                    USR_OP=$(dialog --stdout --menu "Gerenciar usuários FTP" 15 50 10 \
                        1 "Listar e remover usuários" \
                        2 "Adicionar usuário" \
                        0 "Voltar")

                    [ $? -ne 0 ] && break

                    case $USR_OP in
                        1) listar_usuarios ;;
                        2) criar_usuario ;;
                        0) break ;;
                    esac
                done
                ;;
            7)
                editar_configuracao
                ;;
            8)
                systemctl restart vsftpd
                dialog --msgbox "🔄 FTP reiniciado com sucesso." 6 40
                ;;
            0)
                break
                ;;
        esac
    done
}

# --- Menu principal do script ---

main_menu() {
    while true; do
        OPCAO=$(dialog --stdout --menu "Gerenciador vsftpd" 15 50 8 \
            1 "Configurar FTP" \
            0 "Sair")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1) configurar_ftp ;;
            0) break ;;
        esac
    done
}

# --- Executa o menu principal ---
main_menu
clear
