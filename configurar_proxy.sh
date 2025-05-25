#!/bin/bash

# Verificar se é root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Execute este script como root ou com sudo."
    exit 1
fi

# Verificar se dialog está instalado
if ! command -v dialog &> /dev/null; then
    apt update && apt install -y dialog
fi

SQUID_CONF="/etc/squid/squid.conf"

# ========== Instalar Proxy (Squid) ==========
instalar_proxy() {
    (
        echo "10"; sleep 0.5
        echo "# Atualizando pacotes..."; apt update >/dev/null 2>&1
        echo "40"; sleep 0.5
        echo "# Instalando Squid Proxy..."; apt install -y squid >/dev/null 2>&1
        echo "90"; sleep 0.5
        echo "# Habilitando serviço..."
        systemctl enable squid >/dev/null 2>&1
        systemctl restart squid >/dev/null 2>&1
        echo "100"
    ) | dialog --gauge "Instalando Squid Proxy..." 10 60 0

    dialog --msgbox "✅ Squid instalado com sucesso." 7 50
}

# ========== Configurar Proxy ==========
configurar_proxy() {
    OPCAO=$(dialog --stdout --menu "🔧 Configurações de Proxy" 15 60 8 \
        1 "Liberar acesso total (Open Proxy)" \
        2 "Restringir por IP" \
        3 "Definir porta do proxy" \
        4 "Habilitar autenticação (básica)" \
        5 "Verificar configuração atual" \
        0 "Voltar")

    [ $? -ne 0 ] && return

    case $OPCAO in
        1)
            cp $SQUID_CONF ${SQUID_CONF}.bak
            sed -i 's/^http_access deny all/#http_access deny all/' $SQUID_CONF
            grep -q "http_access allow all" $SQUID_CONF || echo "http_access allow all" >> $SQUID_CONF
            systemctl restart squid
            dialog --msgbox "✅ Proxy liberado para qualquer IP (não recomendado para produção)." 8 60
            ;;
        2)
            IP=$(dialog --stdout --inputbox "Informe o IP ou rede a ser liberada (ex.: 192.168.1.0/24)" 8 50)
            [ -z "$IP" ] && return
            echo "acl rede_local src $IP" >> $SQUID_CONF
            sed -i '/http_access allow all/d' $SQUID_CONF
            sed -i 's/^http_access deny all/#http_access deny all/' $SQUID_CONF
            grep -q "http_access allow rede_local" $SQUID_CONF || echo "http_access allow rede_local" >> $SQUID_CONF
            systemctl restart squid
            dialog --msgbox "✅ Acesso liberado para $IP." 7 50
            ;;
        3)
            PORTA=$(dialog --stdout --inputbox "Informe a porta para o Proxy (padrão 3128)" 8 40)
            [ -z "$PORTA" ] && return
            sed -i "s/^http_port .*/http_port $PORTA/" $SQUID_CONF || echo "http_port $PORTA" >> $SQUID_CONF
            systemctl restart squid
            dialog --msgbox "✅ Proxy agora opera na porta $PORTA." 7 50
            ;;
        4)
            apt install -y apache2-utils >/dev/null 2>&1
            mkdir -p /etc/squid
            touch /etc/squid/squid_passwd

            USUARIO=$(dialog --stdout --inputbox "Informe o nome do usuário:" 8 40)
            [ -z "$USUARIO" ] && return
            htpasswd /etc/squid/squid_passwd $USUARIO

            grep -q "auth_param basic program" $SQUID_CONF || cat <<EOF >> $SQUID_CONF

auth_param basic program /usr/lib/squid/basic_ncsa_auth /etc/squid/squid_passwd
auth_param basic realm Proxy
acl autenticados proxy_auth REQUIRED
http_access allow autenticados
EOF
            sed -i 's/^http_access deny all/#http_access deny all/' $SQUID_CONF

            systemctl restart squid
            dialog --msgbox "✅ Autenticação habilitada. Usuário: $USUARIO" 8 50
            ;;
        5)
            dialog --textbox $SQUID_CONF 25 80
            ;;
        0) return ;;
    esac
}

# ========== Gerenciar Proxy ==========
gerenciar_proxy() {
    OPCAO=$(dialog --stdout --menu "🛠️ Gerenciar Proxy" 15 60 6 \
        1 "Iniciar Proxy" \
        2 "Parar Proxy" \
        3 "Reiniciar Proxy" \
        4 "Status do Proxy" \
        0 "Voltar")

    [ $? -ne 0 ] && return

    case $OPCAO in
        1)
            systemctl start squid
            dialog --msgbox "✅ Proxy iniciado." 6 40
            ;;
        2)
            systemctl stop squid
            dialog --msgbox "🛑 Proxy parado." 6 40
            ;;
        3)
            systemctl restart squid
            dialog --msgbox "🔄 Proxy reiniciado." 6 40
            ;;
        4)
            systemctl status squid | tee /tmp/status_proxy
            dialog --textbox /tmp/status_proxy 20 70
            ;;
        0) return ;;
    esac
}

leia_importante() {
    cat <<'EOF' > /tmp/leia_proxy.txt
==============================
      ⚠️ LEIA IMPORTANTE ⚠️
==============================

Este script gerencia o servidor PROXY (Squid).

🔸 Local da configuração: /etc/squid/squid.conf
🔸 Porta padrão: 3128
🔸 Arquivo de senhas (se ativado): /etc/squid/squid_passwd

==============================
💡 Funções principais:
- Liberar acesso total
- Restringir acesso por IP
- Definir porta
- Habilitar autenticação com usuário/senha

==============================
🚫 Segurança:
- Nunca deixe "http_access allow all" se o proxy estiver acessível pela internet.
- Use autenticação ou controle por IP para evitar abuso.
- Proteja a porta no firewall (UFW, iptables, etc.).

==============================
🚀 Acesso ao Proxy:
- Configure seu navegador ou dispositivo para usar o IP do servidor e a porta definida.

Exemplo:
Servidor Proxy: 192.168.1.10
Porta: 3128

==============================
EOF

    dialog --textbox /tmp/leia_proxy.txt 25 80
    rm -f /tmp/leia_proxy.txt
}


# ========== Menu Principal ==========
main_menu() {
    while true; do
        OPCAO=$(dialog --stdout --menu "🌐 Gerenciador Proxy (Squid)" 15 60 6 \
            1 "Instalar Proxy" \
            2 "Configurar Proxy" \
            3 "Gerenciar Proxy" \
            4 "📜 LEIA IMPORTANTE" \
            0 "Sair")

        [ $? -ne 0 ] && break

        case $OPCAO in
            1) instalar_proxy ;;
            2) configurar_proxy ;;
            3) gerenciar_proxy ;;
            4) leia_importante ;;
            0) break ;;
        esac
    done
}

main_menu
