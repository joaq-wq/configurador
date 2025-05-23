#!/bin/bash

# =============================
# Script SSH Master Interativo
# =============================

# 🚀 Verifica e instala SSH + Dialog com barra
if ! dpkg -l | grep -q openssh-server || ! command -v dialog &>/dev/null; then
    (
    echo 10; echo "Atualizando pacotes..."; sleep 1
    apt update -y &>/dev/null
    echo 50; echo "Instalando OpenSSH e Dialog..."; sleep 1
    apt install -y openssh-server dialog &>/dev/null
    echo 100; echo "Finalizando instalação..." ; sleep 1
    ) | dialog --gauge "⏳ Preparando ambiente..." 10 60 0
fi

CONFIG="/etc/ssh/sshd_config"
BACKUP="$CONFIG.bkp.$(date +%F-%H-%M-%S)"
cp $CONFIG $BACKUP

# 🎯 Captura configs atuais
PORTA_ATUAL=$(grep ^Port $CONFIG | awk '{print $2}' || echo "22")
ROOT_ATUAL=$(grep ^PermitRootLogin $CONFIG | awk '{print $2}' || echo "prohibit-password")
PASSWD_AUTH=$(grep ^PasswordAuthentication $CONFIG | awk '{print $2}' || echo "yes")
PUBKEY_AUTH=$(grep ^PubkeyAuthentication $CONFIG | awk '{print $2}' || echo "yes")

# 🗒️ Menu Checklist
OPCOES=$(dialog --stdout --checklist "🛠️ Selecione o que deseja configurar no SSH:" 20 70 10 \
1 "Alterar Porta (Atual: $PORTA_ATUAL)" off \
2 "Permitir Root Login (Atual: $ROOT_ATUAL)" off \
3 "Ativar/Desativar Senha (Atual: $PASSWD_AUTH)" off \
4 "Ativar/Desativar Chave Pública (Atual: $PUBKEY_AUTH)" off \
5 "Ativar Log Verboso (/var/log/auth.log)" off)

[ $? -ne 0 ] && clear && exit

# 🔧 Remove aspas do retorno
OPCOES=$(echo $OPCOES | tr -d '"')

# 🧠 Processa cada opção
for opcao in $OPCOES; do
    case $opcao in

    1)
        PORTA=$(dialog --stdout --inputbox "Digite a nova porta SSH (Atual: $PORTA_ATUAL):" 8 40 "$PORTA_ATUAL")
        if [[ ! "$PORTA" =~ ^[0-9]+$ ]]; then
            dialog --msgbox "❌ Porta inválida. Deve ser um número." 6 40
        else
            sed -i "/^Port /d" $CONFIG
            echo "Port $PORTA" >> $CONFIG
        fi
        ;;

    2)
        ROOT=$(dialog --stdout --menu "Permitir root login?" 10 40 4 \
        yes "Permitir" \
        no "Negar" \
        prohibit-password "Apenas chave pública" \
        without-password "Sem senha")
        sed -i "/^PermitRootLogin /d" $CONFIG
        echo "PermitRootLogin $ROOT" >> $CONFIG
        ;;

    3)
        PASSWD=$(dialog --stdout --menu "Permitir autenticação por senha?" 10 40 2 \
        yes "Sim" no "Não")
        sed -i "/^PasswordAuthentication /d" $CONFIG
        echo "PasswordAuthentication $PASSWD" >> $CONFIG
        ;;

    4)
        PUBKEY=$(dialog --stdout --menu "Permitir autenticação por chave pública?" 10 40 2 \
        yes "Sim" no "Não")
        sed -i "/^PubkeyAuthentication /d" $CONFIG
        echo "PubkeyAuthentication $PUBKEY" >> $CONFIG
        ;;

    5)
        sed -i '/^LogLevel/d' $CONFIG
        echo "LogLevel VERBOSE" >> $CONFIG
        ;;

    esac
done

# 🚀 Reinicia o SSH
systemctl restart ssh

dialog --msgbox "✅ SSH Configurado com sucesso!\n\nBackup salvo em: $BACKUP" 8 50

clear
