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

LOG="/tmp/ftp_install.log"
VSFTPD_CONF="/etc/vsftpd.conf"

# Função para instalar vsftpd
instalar_ftp() {
    rm -f "$LOG"
    (
        apt-get update -qq
        apt-get install -y vsftpd openssl >"$LOG" 2>&1
    ) &
    PID=$!

    (
        SPIN='-\|/'
        i=0
        PROGRESS=5

        while kill -0 $PID 2>/dev/null; do
            if [ -f "$LOG" ]; then
                LINES=$(wc -l < "$LOG")
                TARGET=$((LINES * 3))
                [ "$TARGET" -gt 90 ] && TARGET=90
            else
                TARGET=10
            fi

            if [ "$PROGRESS" -lt "$TARGET" ]; then
                PROGRESS=$((PROGRESS + 1))
            fi

            i=$(( (i + 1) % 4 ))
            echo "$PROGRESS"
            echo "Instalando vsftpd... ${SPIN:$i:1}"
            sleep 0.2
        done

        while [ "$PROGRESS" -lt 100 ]; do
            PROGRESS=$((PROGRESS + 2))
            echo "$PROGRESS"
            echo "Finalizando instalação..."
            sleep 0.1
        done
    ) | dialog --gauge "Instalando vsftpd..." 10 70 0

    wait $PID
    RET=$?

    if [ $RET -eq 0 ]; then
        dialog --msgbox "✅ vsftpd instalado com sucesso!" 6 50
    else
        dialog --msgbox "❌ Erro na instalação. Verifique $LOG" 8 60
        exit 1
    fi
}

# Função para verificar se uma configuração existe
check_config() {
    grep -E "^$1=" "$VSFTPD_CONF" | awk -F= '{print $2}'
}

# Função para alterar ou adicionar configuração
set_config() {
    sed -i "/^$1=/d" "$VSFTPD_CONF"
    echo "$1=$2" >> "$VSFTPD_CONF"
}

# Gerar certificado SSL
gerar_certificado_ssl() {
    mkdir -p /etc/ssl/private
    mkdir -p /etc/ssl/certs

    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
    -keyout /etc/ssl/private/ftp-key.pem \
    -out /etc/ssl/certs/ftp-cert.pem \
    -subj "/C=BR/ST=Estado/L=Cidade/O=MinhaEmpresa/OU=TI/CN=$(hostname)"

    dialog --msgbox "✅ Certificado SSL autoassinado gerado em:\n/etc/ssl/certs/ftp-cert.pem" 8 60
}

# Ativar/Desativar TLS
configurar_tls() {
    SSL_STATUS=$(check_config "ssl_enable")
    if [ "$SSL_STATUS" == "YES" ]; then
        dialog --yesno "TLS/SSL está ativado. Deseja desativar?" 7 50
        if [ $? -eq 0 ]; then
            set_config ssl_enable NO
            dialog --msgbox "🔓 TLS/SSL desativado." 6 40
        fi
    else
        dialog --yesno "Deseja gerar um certificado autoassinado?" 7 50
        if [ $? -eq 0 ]; then
            gerar_certificado_ssl
        fi
        set_config ssl_enable YES
        set_config rsa_cert_file /etc/ssl/certs/ftp-cert.pem
        set_config rsa_private_key_file /etc/ssl/private/ftp-key.pem
        set_config allow_anon_ssl NO
        set_config force_local_data_ssl YES
        set_config force_local_logins_ssl YES
        set_config ssl_tlsv1 YES
        set_config ssl_sslv2 NO
        set_config ssl_sslv3 NO
        dialog --msgbox "🔒 TLS/SSL ativado." 6 40
    fi
}

# Criar usuário FTP
criar_usuario() {
    USER=$(dialog --stdout --inputbox "Digite o nome do usuário:" 8 40)
    [ -z "$USER" ] && return

    PASS=$(dialog --stdout --insecure --passwordbox "Digite a senha do usuário:" 8 40)
    [ -z "$PASS" ] && return

    useradd -m "$USER"
    echo "$USER:$PASS" | chpasswd

    dialog --msgbox "✅ Usuário $USER criado com sucesso!" 6 50
}

# Editar configuração manualmente
editar_configuracao() {
    nano "$VSFTPD_CONF"
}

# Configuração principal
configurar_ftp() {
    while true; do
        ANON=$(check_config "anonymous_enable")
        LOCAL=$(check_config "local_enable")
        WRITE=$(check_config "write_enable")
        CHROOT=$(check_config "chroot_local_user")
        SSL=$(check_config "ssl_enable")

        SUB_OPCAO=$(dialog --stdout --menu "⚙️ Configurar FTP" 20 70 10 \
            1 "Permitir conexões anônimas (Atual: ${ANON:-NO})" \
            2 "Ativar login de usuários locais (Atual: ${LOCAL:-NO})" \
            3 "Permitir upload (Atual: ${WRITE:-NO})" \
            4 "Ativar chroot (travar usuário na pasta) (Atual: ${CHROOT:-NO})" \
            5 "Configurar TLS/SSL (Atual: ${SSL:-NO})" \
            6 "Criar usuário FTP" \
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
                set_config local_enable YES
                dialog --msgbox "✅ Login de usuários locais ativado." 6 50
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
                set_config chroot_local_user YES
                dialog --msgbox "🔐 Usuários agora estão presos em suas pastas home." 6 50
                ;;
            5)
                configurar_tls
                ;;
            6)
                criar_usuario
                ;;
            7)
                editar_configuracao
                ;;
            8)
                systemctl restart vsftpd
                dialog --msgbox "🔄 FTP reiniciado com sucesso." 6 50
                ;;
            0)
                break
                ;;
        esac
    done
}

# Menu principal
while true; do
    OPCAO=$(dialog --stdout --menu "Menu FTP" 15 60 5 \
        1 "Instalar vsftpd" \
        2 "Configurar FTP" \
        0 "Sair")

    [ $? -ne 0 ] && break

    case $OPCAO in
        1)
            instalar_ftp
            ;;
        2)
            configurar_ftp
            ;;
        0)
            break
            ;;
    esac
done

LOG="/tmp/ftp_install.log"

# Função para instalar o vsftpd com barra de progresso
instalar_ftp() {
    rm -f "$LOG"

    (
        apt-get update -qq
        apt-get install -y vsftpd >"$LOG" 2>&1
    ) &
    PID=$!

    (
        SPIN='-\|/'
        i=0
        PROGRESS=5

        while kill -0 $PID 2>/dev/null; do
            if [ -f "$LOG" ]; then
                LINES=$(wc -l < "$LOG")
                TARGET=$((LINES * 3))
                [ "$TARGET" -gt 90 ] && TARGET=90
            else
                TARGET=10
            fi

            if [ "$PROGRESS" -lt "$TARGET" ]; then
                PROGRESS=$((PROGRESS + 1))
            fi

            i=$(( (i + 1) % 4 ))
            echo "$PROGRESS"
            echo "Instalando vsftpd... ${SPIN:$i:1}"
            sleep 0.2
        done

        while [ "$PROGRESS" -lt 100 ]; do
            PROGRESS=$((PROGRESS + 2))
            echo "$PROGRESS"
            echo "Finalizando instalação..."
            sleep 0.1
        done
    ) | dialog --gauge "Instalando vsftpd..." 10 70 0

    wait $PID
    RET=$?

    if [ $RET -eq 0 ]; then
        dialog --msgbox "✅ vsftpd instalado com sucesso!" 6 50
    else
        dialog --msgbox "❌ Erro na instalação. Verifique $LOG" 8 60
        exit 1
    fi
}

# Função para editar configuração do vsftpd
editar_configuracao() {
    nano /etc/vsftpd.conf
}

# Função para aplicar algumas configurações básicas via menu
configurar_ftp() {
    while true; do
        SUB_OPCAO=$(dialog --stdout --menu "⚙️ Configurar FTP" 20 70 10 \
            1 "Permitir conexões anônimas (padrão: NO)" \
            2 "Ativar login de usuários locais" \
            3 "Permitir upload" \
            4 "Ativar chroot (travar usuário na pasta)" \
            5 "Editar manualmente (nano)" \
            6 "Reiniciar FTP" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $SUB_OPCAO in
            1)
                sed -i '/^anonymous_enable=/d' /etc/vsftpd.conf
                dialog --yesno "Permitir conexões anônimas?" 7 50
                if [ $? -eq 0 ]; then
                    echo "anonymous_enable=YES" >> /etc/vsftpd.conf
                else
                    echo "anonymous_enable=NO" >> /etc/vsftpd.conf
                fi
                ;;
            2)
                sed -i '/^local_enable=/d' /etc/vsftpd.conf
                echo "local_enable=YES" >> /etc/vsftpd.conf
                dialog --msgbox "✅ Login de usuários locais ativado." 6 40
                ;;
            3)
                sed -i '/^write_enable=/d' /etc/vsftpd.conf
                dialog --yesno "Permitir upload e escrita?" 7 50
                if [ $? -eq 0 ]; then
                    echo "write_enable=YES" >> /etc/vsftpd.conf
                    dialog --msgbox "✅ Upload ativado." 6 40
                else
                    echo "write_enable=NO" >> /etc/vsftpd.conf
                    dialog --msgbox "🚫 Upload desativado." 6 40
                fi
                ;;
            4)
                sed -i '/^chroot_local_user=/d' /etc/vsftpd.conf
                echo "chroot_local_user=YES" >> /etc/vsftpd.conf
                dialog --msgbox "🔐 Usuários agora estão presos em suas pastas home." 6 50
                ;;
            5)
                editar_configuracao
                ;;
            6)
                systemctl restart vsftpd
                dialog --msgbox "🔄 FTP reiniciado com sucesso." 6 40
                ;;
            0)
                break
                ;;
        esac
    done
}

# Menu principal FTP
while true; do
    OPCAO=$(dialog --stdout --menu "Menu FTP" 15 60 5 \
        1 "Instalar vsftpd" \
        2 "Configurar FTP" \
        0 "Voltar")

    [ $? -ne 0 ] && break

    case $OPCAO in
        1)
            instalar_ftp
            ;;
        2)
            configurar_ftp
            ;;
        0)
            break
            ;;
    esac
done
