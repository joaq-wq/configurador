#!/bin/bash

# Script: Gerenciar Firewall UFW com Dialog

gerenciar_ufw() {
    while true; do
        UFW_OPC=$(dialog --stdout --menu "🔐 Gerenciar Firewall (UFW)" 15 60 6 \
            1 "Abrir Porta (Permitir)" \
            2 "Fechar Porta (Bloquear)" \
            3 "Listar portas abertas" \
            4 "Ativar UFW" \
            5 "Desativar UFW" \
            0 "Voltar")

        [ $? -ne 0 ] && break

        case $UFW_OPC in
            1)
                PORTA=$(dialog --stdout --inputbox "Digite a porta para abrir:" 8 40)
                [ -z "$PORTA" ] && continue
                PROTO=$(dialog --stdout --menu "Escolha o protocolo:" 10 40 2 tcp "TCP" udp "UDP")
                [ -z "$PROTO" ] && continue
                sudo ufw allow $PORTA/$PROTO
                dialog --msgbox "Porta $PORTA/$PROTO aberta com sucesso." 6 50
                ;;
            2)
                PORTA=$(dialog --stdout --inputbox "Digite a porta para bloquear:" 8 40)
                [ -z "$PORTA" ] && continue
                PROTO=$(dialog --stdout --menu "Escolha o protocolo:" 10 40 2 tcp "TCP" udp "UDP")
                [ -z "$PROTO" ] && continue
                sudo ufw deny $PORTA/$PROTO
                dialog --msgbox "Porta $PORTA/$PROTO bloqueada com sucesso." 6 50
                ;;
            3)
                STATUS=$(sudo ufw status numbered)
                dialog --msgbox "Portas abertas e regras:\n\n$STATUS" 20 70
                ;;
            4)
                sudo ufw enable
                dialog --msgbox "Firewall UFW ativado." 6 40
                ;;
            5)
                sudo ufw disable
                dialog --msgbox "Firewall UFW desativado." 6 40
                ;;
            0) break ;;
        esac
    done
}

verifica_instala_ufw() {
    if ! dpkg-query -W -f='${Status}' ufw 2>/dev/null | grep -q "install ok installed"; then
        dialog --infobox "Instalando UFW..." 5 40
        DEBIAN_FRONTEND=noninteractive apt-get update -qq
        DEBIAN_FRONTEND=noninteractive apt-get install -y ufw >/dev/null 2>&1
        dialog --msgbox "UFW instalado com sucesso!" 6 40
    else
        dialog --msgbox "UFW já está instalado." 6 40
    fi
}

# === Menu Principal do Script de Firewall ===

while true; do
    FIRE_OPC=$(dialog --stdout --menu "🔥 Firewall UFW" 12 50 3 \
        1 "Instalar UFW" \
        2 "Gerenciar Firewall" \
        0 "Sair")

    [ $? -ne 0 ] && break

    case $FIRE_OPC in
        1) verifica_instala_ufw ;;
        2) gerenciar_ufw ;;
        0) clear; exit 0 ;;
    esac
done
