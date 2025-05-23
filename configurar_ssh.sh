
#!/bin/bash

# =============================
# Script Master de SSH - by Joaquimkj
# =============================

# Verifica se o dialog está instalado
if ! command -v dialog &> /dev/null; then
    echo "Instalando dialog..."
    apt update && apt install -y dialog
fi

# Função para configurar SSH
configurar_ssh() {
    # Verifica se o OpenSSH está instalado
    if ! dpkg -l | grep -q openssh-server; then
        dialog --title "Instalação do SSH" --msgbox "O OpenSSH não está instalado. Instalando agora..." 7 50
        apt update && apt install -y openssh-server
    fi

    CONFIG="/etc/ssh/sshd_config"

    # Backup
    cp $CONFIG ${CONFIG}.bkp.$(date +%F-%H-%M-%S)

    # Coleta informações atuais
    PORTA_ATUAL=$(grep ^Port $CONFIG | awk '{print $2}')
    [ -z "$PORTA_ATUAL" ] && PORTA_ATUAL="22"

    ROOT_ATUAL=$(grep ^PermitRootLogin $CONFIG | awk '{print $2}')
    [ -z "$ROOT_ATUAL" ] && ROOT_ATUAL="prohibit-password"

    PASSWD_AUTH=$(grep ^PasswordAuthentication $CONFIG | awk '{print $2}')
    [ -z "$PASSWD_AUTH" ] && PASSWD_AUTH="yes"

    PUBKEY_AUTH=$(grep ^PubkeyAuthentication $CONFIG | awk '{print $2}')
    [ -z "$PUBKEY_AUTH" ] && PUBKEY_AUTH="yes"

    ALLOW_USERS=$(grep ^AllowUsers $CONFIG | cut -d' ' -f2-)
    LOGIN_GRACE=$(grep ^LoginGraceTime $CONFIG | awk '{print $2}')
    [ -z "$LOGIN_GRACE" ] && LOGIN_GRACE="120"

    MAX_AUTH_TRIES=$(grep ^MaxAuthTries $CONFIG | awk '{print $2}')
    [ -z "$MAX_AUTH_TRIES" ] && MAX_AUTH_TRIES="6"

    BANNER=$(grep ^Banner $CONFIG | awk '{print $2}')
    [ -z "$BANNER" ] && BANNER="none"

    # Menu checklist
    OPCOES=$(dialog --stdout --checklist "🛠️ Selecione as opções para configurar o SSH:" 20 70 10 \
    1 "Alterar Porta (Atual: $PORTA_ATUAL)" off \
    2 "Permitir Login Root (Atual: $ROOT_ATUAL)" off \
    3 "Permitir Autenticação por Senha (Atual: $PASSWD_AUTH)" off \
    4 "Permitir Autenticação por Chave Pública (Atual: $PUBKEY_AUTH)" off \
    5 "Definir Usuários Permitidos (AllowUsers)" off \
    6 "Definir Tempo Limite de Login (LoginGraceTime: $LOGIN_GRACE)" off \
    7 "Definir Máximo de Tentativas (MaxAuthTries: $MAX_AUTH_TRIES)" off \
    8 "Definir Banner de Aviso (Atual: $BANNER)" off \
    9 "Ver Configuração Atual" off)

    [ $? -ne 0 ] && return

    for opcao in $OPCOES; do
        case $opcao in
            \"1\")
                PORTA=$(dialog --stdout --inputbox "Digite a nova porta SSH:" 8 40 "$PORTA_ATUAL")
                sed -i "/^Port /d" $CONFIG
                echo "Port $PORTA" >> $CONFIG
                ;;
            \"2\")
                ROOT=$(dialog --stdout --menu "Permitir login root?" 10 40 4 \
                yes "Permitir" \
                no "Negar" \
                prohibit-password "Proibir senha (somente chave)" \
                without-password "Apenas chave pública")
                sed -i "/^PermitRootLogin /d" $CONFIG
                echo "PermitRootLogin $ROOT" >> $CONFIG
                ;;
            \"3\")
                PASSWD=$(dialog --stdout --menu "Permitir autenticação por senha?" 10 40 2 \
                yes "Permitir" no "Negar")
                sed -i "/^PasswordAuthentication /d" $CONFIG
                echo "PasswordAuthentication $PASSWD" >> $CONFIG
                ;;
            \"4\")
                PUBKEY=$(dialog --stdout --menu "Permitir autenticação por chave pública?" 10 40 2 \
                yes "Permitir" no "Negar")
                sed -i "/^PubkeyAuthentication /d" $CONFIG
                echo "PubkeyAuthentication $PUBKEY" >> $CONFIG
                ;;
            \"5\")
                USERS=$(dialog --stdout --inputbox "Digite os usuários permitidos separados por espaço:" 8 50 "$ALLOW_USERS")
                sed -i "/^AllowUsers /d" $CONFIG
                echo "AllowUsers $USERS" >> $CONFIG
                ;;
            \"6\")
                GRACE=$(dialog --stdout --inputbox "Tempo limite de login (em segundos, ex: 120):" 8 50 "$LOGIN_GRACE")
                sed -i "/^LoginGraceTime /d" $CONFIG
                echo "LoginGraceTime $GRACE" >> $CONFIG
                ;;
            \"7\")
                MAXTRIES=$(dialog --stdout --inputbox "Número máximo de tentativas de login:" 8 50 "$MAX_AUTH_TRIES")
                sed -i "/^MaxAuthTries /d" $CONFIG
                echo "MaxAuthTries $MAXTRIES" >> $CONFIG
                ;;
            \"8\")
                BANNER_PATH=$(dialog --stdout --inputbox "Digite o caminho do arquivo de banner ou 'none':" 8 60 "$BANNER")
                sed -i "/^Banner /d" $CONFIG
                echo "Banner $BANNER_PATH" >> $CONFIG
                if [ "$BANNER_PATH" != "none" ]; then
                    dialog --stdout --editbox $BANNER_PATH 20 70 || echo "Atenção: Crie ou edite manualmente o arquivo $BANNER_PATH"
                fi
                ;;
            \"9\")
                dialog --msgbox "🔍 Configuração atual:\n\nPorta: $PORTA_ATUAL\nRoot: $ROOT_ATUAL\nSenha: $PASSWD_AUTH\nChave Pública: $PUBKEY_AUTH\nAllowUsers: $ALLOW_USERS\nLoginGraceTime: $LOGIN_GRACE\nMaxAuthTries: $MAX_AUTH_TRIES\nBanner: $BANNER" 20 70
                ;;
        esac
    done

    # Reinicia o serviço SSH
    systemctl restart ssh
    dialog --msgbox "✅ Configurações aplicadas e serviço SSH reiniciado com sucesso!" 7 60
}

# Executa a função
configurar_ssh

clear
echo "Script SSH finalizado com sucesso!"
