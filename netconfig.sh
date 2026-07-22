#!/bin/bash

# =====================================================================
# Script de configurare și diagnosticare rețea - FINAL
# =====================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Directorul de backup (Cerința 7)
BACKUP_DIR="backup"

# --- VALIDARE IP (Cerința 3) ---
validate_ipv4() {
    local ip="$1"
    if [[ "$ip" =~ [[:space:]] ]]; then return 1; fi
    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then return 1; fi

    IFS='.' read -r -a octets <<< "$ip"
    if [ ${#octets[@]} -ne 4 ]; then return 1; fi

    for octet in "${octets[@]}"; do
        if [[ ${#octet} -lt 1 || ${#octet} -gt 3 ]]; then return 1; fi
        if [[ ${#octet} -gt 1 && "$octet" =~ ^0 ]]; then return 1; fi
        if (( octet < 0 || octet > 255 )); then return 1; fi
    done
    return 0
}

# --- VALIDARE ȘI CONVERSIE MASCĂ (Cerința 3) ---
validate_and_get_cidr() {
    local mask="$1"
    local clean_mask="${mask#/}"
    if [[ "$clean_mask" =~ ^[0-9]+$ ]]; then
        if (( clean_mask >= 0 && clean_mask <= 32 )); then
            echo "$clean_mask"
            return 0
        fi
        return 1
    fi

    if [[ ! "$clean_mask" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then return 1; fi

    IFS='.' read -r -a m_octets <<< "$clean_mask"
    if [ ${#m_octets[@]} -ne 4 ]; then return 1; fi

    local binary_mask=""
    for octet in "${m_octets[@]}"; do
        if [[ ${#octet} -gt 1 && "$octet" =~ ^0 ]]; then return 1; fi
        if (( octet < 0 || octet > 255 )); then return 1; fi
        
        local bin=$(printf "%08d" "$(echo "obase=2; $octet" | bc 2>/dev/null)")
        binary_mask="${binary_mask}${bin}"
    done

    if [[ "$binary_mask" =~ 01 ]]; then return 1; fi

    local cidr=$(echo "$binary_mask" | tr -cd '1' | wc -c)
    echo "$cidr"
    return 0
}

# --- CERINȚA 1: Detectarea automată a interfețelor ---
list_interfaces() {
    echo -e "\n${BLUE}=== Interfețe de rețea disponibile ===${NC}"
    printf "%-12s %-10s %-20s\n" "Interfață" "Stare" "Adresă IPv4"
    printf "%-12s %-10s %-20s\n" "---------" "------" "------------"

    while read -r line; do
        local iface=$(echo "$line" | awk '{print $2}' | tr -d ':')
        local state="DOWN"
        if echo "$line" | grep -q "state UP"; then state="UP";
        elif echo "$line" | grep -q "state UNKNOWN"; then state="UNKNOWN"; fi

        local ip=$(ip -4 addr show dev "$iface" | grep inet | awk '{print $2}' | head -n 1)
        if [ -z "$ip" ]; then ip="Fără IP"; fi

        printf "%-12s %-10s %-20s\n" "$iface" "$state" "$ip"
    done < <(ip -o link show)
    echo ""
}

# --- CERINȚA 2 & 3: Administrare adrese IPv4 ---
manage_interface() {
    list_interfaces
    read -p "Alege interfața pe care vrei să o configurezi (ex: eth0): " IFACE

    if ! ip link show "$IFACE" > /dev/null 2>&1; then
        echo -e "${RED}Eroare: Interfața '$IFACE' nu există!${NC}"
        return 1
    fi

    while true; do
        echo -e "\n${BLUE}--- Administrare interfață: $IFACE ---${NC}"
        echo "1. Afișează adresele configurate"
        echo "2. Adaugă o adresă IPv4"
        echo "3. Șterge o adresă IPv4"
        echo "4. Înlocuiește adresa existentă"
        echo "5. Înapoi la meniul principal"
        read -p "Opțiune: " opt

        case $opt in
            1)
                echo -e "\n${YELLOW}Adrese configurate pe $IFACE:${NC}"
                ip -4 addr show dev "$IFACE" | grep inet | awk '{print $2}' || echo "Nicio adresă configurată."
                ;;
            2)
                read -p "Introdu adresa IPv4: " NEW_IP
                if ! validate_ipv4 "$NEW_IP"; then echo -e "${RED}Eroare: IP invalid!${NC}"; continue; fi
                read -p "Introdu masca (ex: /24 sau 255.255.255.0): " RAW_MASK
                CIDR=$(validate_and_get_cidr "$RAW_MASK")
                if [ $? -ne 0 ]; then echo -e "${RED}Eroare: Mască invalidă!${NC}"; continue; fi

                if ip addr show dev "$IFACE" | grep -q "$NEW_IP/"; then
                    echo -e "${YELLOW}Atenție: Adresa este deja configurată!${NC}"
                else
                    sudo ip addr add "$NEW_IP/$CIDR" dev "$IFACE" && echo -e "${GREEN}Adresă adăugată!${NC}"
                fi
                ;;
            3)
                ip -4 addr show dev "$IFACE" | grep inet | awk '{print $2}'
                read -p "Introdu adresa de șters (ex: 192.168.1.10/24): " IP_DEL
                if [ -z "$IP_DEL" ]; then continue; fi
                read -p "Confirmi ștergerea? (y/n): " confirm
                if [[ "$confirm" =~ ^[yY]$ ]]; then sudo ip addr del "$IP_DEL" dev "$IFACE" && echo -e "${GREEN}Ștearsă!${NC}"; fi
                ;;
            4)
                read -p "Introdu noua adresă IPv4: " NEW_IP
                if ! validate_ipv4 "$NEW_IP"; then echo -e "${RED}Eroare!${NC}"; continue; fi
                read -p "Introdu masca: " RAW_MASK
                CIDR=$(validate_and_get_cidr "$RAW_MASK")
                if [ $? -ne 0 ]; then echo -e "${RED}Mască invalidă!${NC}"; continue; fi

                sudo ip addr flush dev "$IFACE"
                sudo ip addr add "$NEW_IP/$CIDR" dev "$IFACE" && echo -e "${GREEN}Înlocuită cu succes!${NC}"
                ;;
            5) break ;;
            *) echo "Opțiune invalidă!" ;;
        esac
    done
}

# --- CERINȚA 4: Configurarea rutelor ---
manage_routes() {
    while true; do
        echo -e "\n${BLUE}=== Administrare Rute (Cerința 4) ===${NC}"
        echo "1. Afișează tabela de rutare"
        echo "2. Configurează Gateway-ul implicit"
        echo "3. Șterge Gateway-ul implicit"
        echo "4. Adaugă o rută către o rețea"
        echo "5. Șterge o rută specifică"
        echo "6. Înapoi la meniul principal"
        read -p "Opțiune: " route_opt

        case $route_opt in
            1) ip route show ;;
            2)
                read -p "IP Gateway: " GW_IP
                read -p "Interfață: " GW_IFACE
                if validate_ipv4 "$GW_IP"; then
                    sudo ip route add default via "$GW_IP" dev "$GW_IFACE" 2>/dev/null || sudo ip route replace default via "$GW_IP" dev "$GW_IFACE"
                    echo -e "${GREEN}Gateway setat!${NC}"
                fi
                ;;
            3) sudo ip route del default && echo -e "${GREEN}Gateway implicit șters!${NC}" ;;
            4)
                read -p "Rețea destinație (ex: 192.168.2.0): " NET_IP
                read -p "Mască (ex: 24): " RAW_MASK
                CIDR=$(validate_and_get_cidr "$RAW_MASK")
                read -p "Via IP (Gateway): " VIA_IP
                sudo ip route add "$NET_IP/$CIDR" via "$VIA_IP" && echo -e "${GREEN}Rută adăugată!${NC}"
                ;;
            5)
                read -p "Introdu ruta de șters (ex: 192.168.2.0/24): " ROUTE_DEL
                sudo ip route del "$ROUTE_DEL" && echo -e "${GREEN}Rută ștearsă!${NC}"
                ;;
            6) break ;;
        esac
    done
}

# --- CERINȚA 5: Verificarea și diagnosticarea conectivității ---
diagnose_network() {
    echo -e "\n${BLUE}=== Diagnosticare Automată Conectivitate (Cerința 5) ===${NC}"
    read -p "Alege interfața pentru testare (ex: eth0): " DIAG_IFACE

    if ! ip link show "$DIAG_IFACE" > /dev/null 2>&1; then
        echo -e "${RED}[EROARE] Interfața nu există!${NC}"
        return 1
    fi

    if ip link show "$DIAG_IFACE" | grep -q "state UP"; then
        echo -e "${GREEN}[OK] Interfața $DIAG_IFACE este activă (UP).${NC}"
    else
        echo -e "${RED}[FAIL] Interfața $DIAG_IFACE este oprită (DOWN).${NC}"
    fi

    local has_ip=$(ip -4 addr show dev "$DIAG_IFACE" | grep inet | awk '{print $2}')
    if [ -n "$has_ip" ]; then
        echo -e "${GREEN}[OK] Interfața are IP: $has_ip${NC}"
    else
        echo -e "${RED}[FAIL] Interfața nu are nicio adresă IPv4 configurată.${NC}"
    fi

    local has_gw=$(ip route show default | awk '{print $3}')
    if [ -n "$has_gw" ]; then
        echo -e "${GREEN}[OK] Rută implicită detectată prin gateway-ul: $has_gw${NC}"
        if ping -c 2 -W 2 "$has_gw" > /dev/null 2>&1; then
            echo -e "${GREEN}[OK] Gateway-ul ($has_gw) răspunde la PING.${NC}"
        else
            echo -e "${RED}[FAIL] Gateway-ul ($has_gw) NU răspunde la PING!${NC}"
        fi
    else
        echo -e "${RED}[FAIL] Nu există o rută implicită (Default Gateway) în sistem.${NC}"
    fi

    if ping -c 2 -W 2 8.8.8.8 > /dev/null 2>&1; then
        echo -e "${GREEN}[OK] Conectivitatea WAN funcționează (IP extern 8.8.8.8 răspunde).${NC}"
    else
        echo -e "${RED}[FAIL] IP-ul extern (8.8.8.8) nu răspunde. Lipsă internet?${NC}"
    fi

    if host google.com > /dev/null 2>&1 || nslookup google.com > /dev/null 2>&1; then
        echo -e "${GREEN}[OK] Rezoluția DNS funcționează (google.com a fost rezolvat).${NC}"
        if ping -c 2 -W 2 google.com > /dev/null 2>&1; then
            echo -e "${GREEN}[OK] Destinația finală (google.com) este complet accesibilă.${NC}"
        else
            echo -e "${RED}[FAIL] Numele s-a rezolvat, dar destinația finală nu răspunde la PING.${NC}"
        fi
    else
        echo -e "${RED}[FAIL] Rezoluția DNS a eșuat. Serverele DNS nu funcționează.${NC}"
    fi
}

# --- CERINȚA 6: Conexiuni și porturi active ---
monitor_connections() {
    while true; do
        echo -e "\n${BLUE}=== Monitorizare Conexiuni și Porturi Active (Cerința 6) ===${NC}"
        echo "1. Afișează porturile TCP aflate în ascultare (Listening)"
        echo "2. Afișează porturile UDP active"
        echo "3. Afișează conexiunile TCP active (Established)"
        echo "4. Filtrare după PORT sau PROCES"
        echo "5. Înapoi la meniul principal"
        read -p "Opțiune: " ss_opt

        case $ss_opt in
            1) ss -tlnp ;;
            2) ss -unap ;;
            3) ss -tanp state established ;;
            4)
                read -p "Introdu numărul de port sau proces (ex: 80, sshd): " FILTER
                if [ -n "$FILTER" ]; then ss -tupan | grep -i "$FILTER" || echo "Nu s-au găsit conexiuni."; fi
                ;;
            5) break ;;
            *) echo "Opțiune invalidă!" ;;
        esac
    done
}

# --- CERINȚA 7: Backup și Restaurare ---
backup_and_restore() {
    mkdir -p "$BACKUP_DIR"

    while true; do
        echo -e "\n${BLUE}=== Backup și Restaurare Configurație (Cerința 7) ===${NC}"
        echo "1. Salvează configurația curentă (Backup)"
        echo "2. Restaurează o configurație dintr-un fișier (Restore)"
        echo "3. Vezi fișierele de backup disponibile"
        echo "4. Înapoi la meniul principal"
        read -p "Opțiune: " bk_opt

        case $bk_opt in
            1)
                local timestamp=$(date +"%Y-%m-%d_%H-%M-%S")
                local filepath="$BACKUP_DIR/config_backup_$timestamp.txt"

                echo "# FISIER BACKUP RETEA - $timestamp" > "$filepath"
                echo "# FORMAT: IP|INTERFACE|ADDRESS_CIDR" >> "$filepath"

                # Salvare Adrese IP în format executabil/parsabil
                while read -r line; do
                    local iface=$(echo "$line" | awk '{print $2}' | tr -d ':')
                    while read -r ip_line; do
                        local cidr=$(echo "$ip_line" | awk '{print $2}')
                        if [ -n "$cidr" ]; then
                            echo "ADDR|$iface|$cidr" >> "$filepath"
                        fi
                    done < <(ip -4 addr show dev "$iface" | grep inet)
                done < <(ip -o link show)

                # Salvare Rute
                while read -r route_line; do
                    echo "ROUTE|$route_line" >> "$filepath"
                done < <(ip route show)

                echo -e "${GREEN}Configurație salvată cu succes în: $filepath${NC}"
                ;;
            2)
                echo -e "\n${YELLOW}Fișiere de backup disponibile:${NC}"
                ls -1 "$BACKUP_DIR" 2>/dev/null || echo "Niciun backup găsit."
                read -p "Introdu numele fișierului pentru restaurare: " filename
                local target="$BACKUP_DIR/$filename"

                if [ ! -f "$target" ]; then
                    echo -e "${RED}Fișierul nu există!${NC}"
                    continue
                fi

                read -p "Atenție: Această acțiune va aplica setările din fișier. Continui? (y/n): " confirm
                if [[ "$confirm" =~ ^[yY]$ ]]; then
                    echo -e "${YELLOW}Se restaurează configurația...${NC}"
                    
                    while IFS= read -r line; do
                        # Ignorăm comentariile sau liniile goale
                        [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue

                        local type=$(echo "$line" | cut -d'|' -f1)

                        if [ "$type" == "ADDR" ]; then
                            local iface=$(echo "$line" | cut -d'|' -f2)
                            local addr=$(echo "$line" | cut -d'|' -f3)
                            sudo ip addr add "$addr" dev "$iface" 2>/dev/null
                        elif [ "$type" == "ROUTE" ]; then
                            local route_cmd=$(echo "$line" | cut -d'|' -f2-)
                            sudo ip route add $route_cmd 2>/dev/null
                        fi
                    done < "$target"
                    echo -e "${GREEN}Restaurare finalizată!${NC}"
                fi
                ;;
            3)
                echo -e "\n${YELLOW}Conținut director $BACKUP_DIR:${NC}"
                ls -lh "$BACKUP_DIR"
                ;;
            4) break ;;
            *) echo "Opțiune invalidă!" ;;
        esac
    done
}

# --- CERINȚA 8 (SUPLIMENTARĂ): Afișare Serveri DNS ---
show_dns_info() {
    echo -e "\n${BLUE}=== Configurație DNS Curentă (/etc/resolv.conf) ===${NC}"
    if [ -f /etc/resolv.conf ]; then
        grep -E "nameserver|search|domain" /etc/resolv.conf || cat /etc/resolv.conf
    else
        echo -e "${RED}Fișierul /etc/resolv.conf nu a fost găsit!${NC}"
    fi
}

# --- CERINȚA 9 (SUPLIMENTARĂ): Restart Interfață de Rețea ---
restart_interface() {
    list_interfaces
    read -p "Introdu numele interfeței pe care dorești să o resetezi (ex: eth0): " R_IFACE
    if ! ip link show "$R_IFACE" > /dev/null 2>&1; then
        echo -e "${RED}Interfața nu există!${NC}"
        return 1
    fi

    echo -e "${YELLOW}Se oprește interfața $R_IFACE...${NC}"
    sudo ip link set dev "$R_IFACE" down
    sleep 1
    echo -e "${GREEN}Se repornește interfața $R_IFACE...${NC}"
    sudo ip link set dev "$R_IFACE" up
    echo -e "${GREEN}Interfața $R_IFACE a fost resetată cu succes!${NC}"
}

# --- MENIUL PRINCIPAL ---
while true; do
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}      NetConfig - Instrument Rețea       ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "1. Detectare automată interfețe (Cerința 1)"
    echo "2. Configurare interfață & IPv4 (Cerințele 2 & 3)"
    echo "3. Administrare Rute & Gateway (Cerința 4)"
    echo "4. Diagnosticare automată conectivitate (Cerința 5)"
    echo "5. Monitorizare conexiuni & porturi ss (Cerința 6)"
    echo "6. Backup și Restaurare configurație (Cerința 7)"
    echo "7. Afișare servere DNS (Cerința 8 - Suplimentar)"
    echo "8. Repornire/Restart interfață (Cerința 9 - Suplimentar)"
    echo "9. Ieșire"
    read -p "Selectează opțiunea: " main_opt

    case $main_opt in
        1) list_interfaces ;;
        2) manage_interface ;;
        3) manage_routes ;;
        4) diagnose_network ;;
        5) monitor_connections ;;
        6) backup_and_restore ;;
        7) show_dns_info ;;
        8) restart_interface ;;
        9) echo "La revedere!"; exit 0 ;;
        *) echo "Opțiune invalidă!" ;;
    esac
done
