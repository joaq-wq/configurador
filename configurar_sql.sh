#!/bin/bash

# Verificar root
if [ "$EUID" -ne 0 ]; then
    echo "Execute como root ou com sudo."
    exit 1
fi

# Verifica dependências dialog e mysql-server
if ! command -v dialog &>/dev/null; then
    apt-get update && apt-get install -y dialog
fi

MYSQL_CMD="mysql -uroot"
MYSQL_PASS=""

# Instalar MySQL/MariaDB
instalar_mysql() {
    if command -v mysql &>/dev/null; then
        dialog --msgbox "✅ MySQL/MariaDB já instalado." 6 40
        return
    fi
    (
        echo "10" ; sleep 0.5
        echo "# Atualizando pacotes..." ; apt update -y >/dev/null 2>&1
        echo "50" ; sleep 0.5
        echo "# Instalando mysql-server..." ; apt install -y mysql-server dialog >/dev/null 2>&1
        echo "90" ; sleep 0.5
        echo "# Finalizando..." ; sleep 1
        echo "100"
    ) | dialog --gauge "Instalando MySQL/MariaDB..." 10 60 0
    dialog --msgbox "✅ MySQL/MariaDB instalado com sucesso!" 6 40
}

# Função para tentar conexão mysql
tenta_conexao() {
    if [ -z "$MYSQL_PASS" ]; then
        $MYSQL_CMD -e ";" &>/dev/null && return 0
        # Tenta sem senha falhou, pede senha
        MYSQL_PASS=$(dialog --stdout --insecure --passwordbox "Digite a senha root do MySQL/MariaDB:" 8 50)
        [ -z "$MYSQL_PASS" ] && return 1
        MYSQL_CMD="mysql -uroot -p$MYSQL_PASS"
        $MYSQL_CMD -e ";" &>/dev/null && return 0 || return 1
    else
        $MYSQL_CMD -e ";" &>/dev/null && return 0 || return 1
    fi
}

# Listar bancos de dados
listar_bancos() {
    DBS=$($MYSQL_CMD -e "SHOW DATABASES;" -s --skip-column-names 2>/dev/null)
    if [ $? -ne 0 ]; then
        dialog --msgbox "❌ Falha ao listar bancos." 6 40
        return
    fi
    dialog --title "Bancos de Dados" --msgbox "$DBS" 20 50
}

# Listar usuários
listar_usuarios() {
    USERS=$($MYSQL_CMD -e "SELECT User, Host FROM mysql.user;" -s --skip-column-names 2>/dev/null)
    if [ $? -ne 0 ]; then
        dialog --msgbox "❌ Falha ao listar usuários." 6 50
        return
    fi
    dialog --title "Usuários MySQL" --msgbox "$USERS" 20 60
}

# Criar banco de dados
criar_banco() {
    DB_NAME=$(dialog --stdout --inputbox "Nome do banco de dados para criar:" 8 40)
    [ -z "$DB_NAME" ] && return
    $MYSQL_CMD -e "CREATE DATABASE \`$DB_NAME\`;" 2>/dev/null
    if [ $? -eq 0 ]; then
        dialog --msgbox "✅ Banco '$DB_NAME' criado." 6 40
    else
        dialog --msgbox "❌ Falha ao criar banco '$DB_NAME'." 6 40
    fi
}

# Remover banco de dados
remover_banco() {
    DB_NAME=$(dialog --stdout --inputbox "Nome do banco de dados para remover:" 8 40)
    [ -z "$DB_NAME" ] && return
    dialog --yesno "Confirma remoção do banco '$DB_NAME'?" 7 50
    if [ $? -eq 0 ]; then
        $MYSQL_CMD -e "DROP DATABASE \`$DB_NAME\`;" 2>/dev/null
        if [ $? -eq 0 ]; then
            dialog --msgbox "🗑️ Banco '$DB_NAME' removido." 6 40
        else
            dialog --msgbox "❌ Falha ao remover banco '$DB_NAME'." 6 40
        fi
    fi
}

# Criar usuário
criar_usuario() {
    USERNAME=$(dialog --stdout --inputbox "Nome do usuário MySQL para criar:" 8 40)
    [ -z "$USERNAME" ] && return
    PASSWD=$(dialog --stdout --insecure --passwordbox "Senha para o usuário $USERNAME:" 8 40)
    [ -z "$PASSWD" ] && return
    HOSTNAME=$(dialog --stdout --inputbox "Host permitido para o usuário (default: localhost):" 8 50)
    HOSTNAME=${HOSTNAME:-localhost}

    $MYSQL_CMD -e "CREATE USER '$USERNAME'@'$HOSTNAME' IDENTIFIED BY '$PASSWD'; GRANT ALL PRIVILEGES ON *.* TO '$USERNAME'@'$HOSTNAME' WITH GRANT OPTION; FLUSH PRIVILEGES;" 2>/dev/null
    if [ $? -eq 0 ]; then
        dialog --msgbox "✅ Usuário '$USERNAME' criado com acesso total." 6 50
    else
        dialog --msgbox "❌ Falha ao criar usuário '$USERNAME'." 6 50
    fi
}

# Remover usuário
remover_usuario() {
    USERNAME=$(dialog --stdout --inputbox "Nome do usuário MySQL para remover:" 8 40)
    [ -z "$USERNAME" ] && return
    HOSTNAME=$(dialog --stdout --inputbox "Host do usuário (default: localhost):" 8 50)
    HOSTNAME=${HOSTNAME:-localhost}

    dialog --yesno "Confirma remoção do usuário '$USERNAME'@'$HOSTNAME'?" 7 60
    if [ $? -eq 0 ]; then
        $MYSQL_CMD -e "DROP USER '$USERNAME'@'$HOSTNAME'; FLUSH PRIVILEGES;" 2>/dev/null
        if [ $? -eq 0 ]; then
            dialog --msgbox "🗑️ Usuário '$USERNAME' removido." 6 50
        else
            dialog --msgbox "❌ Falha ao remover usuário '$USERNAME'." 6 50
        fi
    fi
}

# Mostrar configurações atuais
mostrar_configs() {
    ROOT_HOSTS=$($MYSQL_CMD -e "SELECT Host FROM mysql.user WHERE User='root';" -s --skip-column-names 2>/dev/null | paste -sd "," -)
    HAS_PASS=$($MYSQL_CMD -e "SELECT authentication_string FROM mysql.user WHERE User='root' AND authentication_string != '';" -s --skip-column-names 2>/dev/null)
    if [ -z "$HAS_PASS" ]; then
        PASS_MSG="Senha root NÃO configurada."
    else
        PASS_MSG="Senha root configurada."
    fi

    # Exibe variáveis importantes do servidor
    VARS=$($MYSQL_CMD -e "SHOW VARIABLES WHERE Variable_name LIKE '%timeout%' OR Variable_name LIKE '%buffer%' OR Variable_name LIKE '%max%';" 2>/dev/null)

    MSG="Hosts autorizados para root: $ROOT_HOSTS\n$PASS_MSG\n\nVariáveis importantes:\n$VARS"
    dialog --title "Configurações MySQL/MariaDB" --msgbox "$MSG" 25 70
}

# Alterar senha root
alterar_senha_root() {
    NOVA_SENHA=$(dialog --stdout --insecure --passwordbox "Digite a nova senha para root:" 8 50)
    [ -z "$NOVA_SENHA" ] && return

    $MYSQL_CMD -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '${NOVA_SENHA}'; FLUSH PRIVILEGES;" 2>/dev/null
    if [ $? -eq 0 ]; then
        dialog --msgbox "✅ Senha root alterada com sucesso!" 6 50
        MYSQL_PASS="$NOVA_SENHA"
        MYSQL_CMD="mysql -uroot -p$MYSQL_PASS"
    else
        dialog --msgbox "❌ Falha ao alterar senha root." 6 50
    fi
}

# Backup banco de dados
backup_banco() {
    DB_NAME=$(dialog --stdout --inputbox "Banco de dados para backup:" 8 40)
    [ -z "$DB_NAME" ] && return

    DESTINO=$(dialog --stdout --inputbox "Caminho para salvar backup (ex: /root/backup.sql):" 8 60)
    [ -z "$DESTINO" ] && return

    mysqldump -uroot -p"$MYSQL_PASS" "$DB_NAME" > "$DESTINO" 2>/dev/null
    if [ $? -eq 0 ]; then
        dialog --msgbox "✅ Backup criado em $DESTINO" 6 50
    else
        dialog --msgbox "❌ Falha ao criar backup." 6 50
    fi
}

# Restaurar backup
restaurar_backup() {
    ARQUIVO=$(dialog --stdout --fselect "$HOME/" 14 60)
    [ -z "$ARQUIVO" ] && return
    if [ ! -f "$ARQUIVO" ]; then
        dialog --msgbox "❌ Arquivo não encontrado." 6 40
        return
    fi

    DB_NAME=$(dialog --stdout --inputbox "Banco de dados para restaurar:" 8 40)
    [ -z "$DB_NAME" ] && return

    $MYSQL_CMD -e "CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;" 2>/dev/null
    mysql -uroot -p"$MYSQL_PASS" "$DB_NAME" < "$ARQUIVO"
    if [ $? -eq 0 ]; then
        dialog --msgbox "✅ Backup restaurado em $DB_NAME" 6 50
    else
        dialog --msgbox "❌ Falha ao restaurar backup." 6 50
    fi
}

menu_principal() {
    while true; do
        opcao=$(dialog --stdout --menu "Gerenciamento MySQL/MariaDB" 20 60 15 \
        1 "Instalar MySQL/MariaDB" \
        2 "Listar bancos de dados" \
        3 "Listar usuários" \
        4 "Criar banco de dados" \
        5 "Remover banco de dados" \
        6 "Criar usuário" \
        7 "Remover usuário" \
        8 "Mostrar configurações atuais" \
        9 "Alterar senha root" \
        10 "Backup banco de dados" \
        11 "Restaurar backup" \
        0 "Sair")

        case $opcao in
            1) instalar_mysql ;;
            2) if tenta_conexao; then listar_bancos; else dialog --msgbox "❌ Falha na conexão MySQL." 6 40; fi ;;
            3) if tenta_conexao; then listar_usuarios; else dialog --msgbox "❌ Falha na conexão MySQL." 6 40; fi ;;
            4) if tenta_conexao; then criar_banco; else dialog --msgbox "❌ Falha na conexão MySQL." 6 40; fi ;;
            5) if tenta_conexao; then remover_banco; else dialog --msgbox "❌ Falha na conexão MySQL." 6 40; fi ;;
            6) if tenta_conexao; then criar_usuario; else dialog --msgbox "❌ Falha na conexão MySQL." 6 40; fi ;;
            7) if tenta_conexao; then remover_usuario; else dialog --msgbox "❌ Falha na conexão MySQL." 6 40; fi ;;
            8) if tenta_conexao; then mostrar_configs; else dialog --msgbox "❌ Falha na conexão MySQL." 6 40; fi ;;
            9) if tenta_conexao; then alterar_senha_root; else dialog --msgbox "❌ Falha na conexão MySQL." 6 40; fi ;;
            10) if tenta_conexao; then backup_banco; else dialog --msgbox "❌ Falha na conexão MySQL." 6 40; fi ;;
            11) if tenta_conexao; then restaurar_backup; else dialog --msgbox "❌ Falha na conexão MySQL." 6 40; fi ;;
            0) clear; exit 0 ;;
            *) dialog --msgbox "Opção inválida." 6 30 ;;
        esac
    done
}

menu_principal
