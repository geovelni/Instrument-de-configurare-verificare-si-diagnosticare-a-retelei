#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- FUNCȚIE VALIDARE IP ---

validate_ipv4() {
    local ip="$1"
    
    if [[ "$ip" =~ [[:space:]] ]]; then
        return 1
    fi

    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        return 1
    fi

    IFS='.' read -r -a octets <<< "$ip"

    if [ ${#octets[@]} -ne 4 ]; then
        return 1
    fi

    for octet in "${octets[@]}"; do

        if [[ ${#octet} -lt 1 || ${#octet} -gt 3 ]]; then
            return 1
        fi

        if [[ ${#octet} -gt 1 && "$octet" =~ ^0 ]]; then
            return 1
        fi

        if (( octet < 0 || octet > 255 )); then
            return 1
        fi
    done

    return 0
}


list_interfaces() {
    echo -e "\n${BLUE}=== Interfețe de rețea disponibile ===${NC}"
    printf "%-12s %-10s %-20s\n" "Interfață" "Stare" "Adresă IPv4"
    printf "%-12s %-10s %-20s\n" "---------" "------" "------------"

    while read -r line; do
        local iface=$(echo "$line" | awk -f /dev/null '{print $2}' | tr -d ':')
        local state="DOWN"
        if echo "$line" | grep -q "state UP"; then
            state="UP"
        elif echo "$line" | grep -q "state UNKNOWN"; then
            state="UNKNOWN"
        fi


        local ip=$(ip -4 addr show dev "$iface" | grep inet | awk '{print $2}' | head -n 1)
        if [ -z "$ip" ]; then
            ip="Fără IP"
        fi

        printf "%-12s %-10s %-20s\n" "$iface" "$state" "$ip"
    done < <(ip -o link show)
    echo ""
}


manage_interface() {
    list_interfaces
    read -p "Alege interfața pe care vrei să o configurezi (ex: eth0, wlan0): " IFACE

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
                read -p "Introdu adresa IPv4 (ex: 192.168.1.100): " NEW_IP
                if ! validate_ipv4 "$NEW_IP"; then
                    echo -e "${RED}Eroare: Adresa IP nu este validă! (Verifică zerourile nesemnificative sau limitele octeților)${NC}"
                    continue
                fi

                read -p "Introdu masca (ex: /24 sau prefix simplu 24): " MASK
                # Corectare format mască dacă utilizatorul uită să pună "/"
                if [[ ! "$MASK" =~ ^/ ]]; then
                    MASK="/$MASK"
                fi

                # Verificăm dacă adresa pe care vrem să o adăugăm există deja configurată
                if ip addr show dev "$IFACE" | grep -q "$NEW_IP/"; then
                    echo -e "${YELLOW}Atenție: Adresa $NEW_IP este deja configurată pe interfața $IFACE!${NC}"
                else
                    echo -e "${GREEN}Configurare propusă: $NEW_IP$MASK pe $IFACE${NC}"
                    read -p "Confirmi aplicarea? (y/n): " confirm
                    if [[ "$confirm" =~ ^[yY]$ ]]; then
                        # Rularea comenzii necesită drepturi de root (sudo)
                        sudo ip addr add "$NEW_IP$MASK" dev "$IFACE"
                        if [ $? -eq 0 ]; then
                            echo -e "${GREEN}Adresa a fost adăugată cu succes!${NC}"
                        else
                            echo -e "${RED}Eroare la aplicarea adresei. Rulează scriptul cu sudo?${NC}"
                        fi
                    else
                        echo "Operațiune anulată."
                    fi
                fi
                ;;
            3)
                echo -e "\n${YELLOW}Adrese active pe $IFACE:${NC}"
                ip -4 addr show dev "$IFACE" | grep inet | awk '{print $2}'
                read -p "Introdu adresa pe care dorești să o ștergi (cu tot cu mască, ex: 192.168.1.100/24): " IP_DEL
                
                if [ -z "$IP_DEL" ]; then
                    echo -e "${RED}Eroare: Câmp gol!${NC}"
                    continue
                fi

                read -p "Sigur vrei să ștergi adresa $IP_DEL? (y/n): " confirm
                if [[ "$confirm" =~ ^[yY]$ ]]; then
                    sudo ip addr del "$IP_DEL" dev "$IFACE"
                    if [ $? -eq 0 ]; then
                        echo -e "${GREEN}Adresă ștearsă cu succes!${NC}"
                    else
                        echo -e "${RED}Eroare la ștergerea adresei.${NC}"
                    fi
                fi
                ;;
            4)
                echo -e "\n${YELLOW}Atenție: Înlocuirea va șterge TOATE adresele actuale de pe $IFACE și va seta una nouă!${NC}"
                read -p "Sigur dorești să continui? (y/n): " confirm_replace
                if [[ ! "$confirm_replace" =~ ^[yY]$ ]]; then
                    echo "Operațiune anulată."
                    continue
                fi

                read -p "Introdu noua adresă IPv4: " NEW_IP
                if ! validate_ipv4 "$NEW_IP"; then
                    echo -e "${RED}Eroare: Adresă invalidă!${NC}"
                    continue
                fi
                read -p "Introdu masca (ex: 24): " MASK
                if [[ ! "$MASK" =~ ^/ ]]; then
                    MASK="/$MASK"
                fi

                # Ștergem adresele vechi
                sudo ip addr flush dev "$IFACE"
                # Adăugăm adresa nouă
                sudo ip addr add "$NEW_IP$MASK" dev "$IFACE"
                echo -e "${GREEN}Adresa a fost înlocuită cu succes!${NC}"
                ;;
            5)
                break
                ;;
            *)
                echo "Opțiune invalidă!"
                ;;
        esac
    done
}

# --- MENIUL PRINCIPAL ---
while true; do
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}      NetConfig - Instrument Rețea       ${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "1. Detectare automată interfețe (Cerința 1)"
    echo "2. Configurare interfață & IPv4 (Cerința 2)"
    echo "3. Ieșire"
    read -p "Selectează opțiunea: " main_opt

    case $main_opt in
        1) list_interfaces ;;
        2) manage_interface ;;
        3) echo "La revedere!"; exit 0 ;;
        *) echo "Opțiune invalidă!" ;;
    esac
done

