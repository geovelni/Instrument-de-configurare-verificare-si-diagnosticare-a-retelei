# Instrument-de-configurare-verificare-si-diagnosticare-a-retelei

## 🎯 Obiectivul Final

Obiectivul principal al proiectului este furnizarea unui utilitar complet, robust și ușor de utilizat de către administratorii de sistem pentru:
1. **Configurarea automată și rapidă** a parametrilor de rețea (interfețe, adrese IP, măști, rute).
2. **Validarea matematică strictă** a datelor introduse de utilizator pentru a preveni erorile de configurare (ex: zerouri nesemnificative, măști invalide).
3. **Diagnosticarea stării conectivității** la nivel local, gateway și WAN prin teste automate.
4. **Analiza porturilor și a conexiunilor active** în timp real cu posibilitatea de filtrare.
5. **Salvarea și restaurarea automată (Backup & Restore)** a întregii configurații de rețea dintr-un director dedicat.

---

## 🛠️ Descrierea Detaliată a Cerințelor și a Pașilor Implementați

### 🔹 Cerința 1: Detectarea automată a interfețelor de rețea
* **Ce realizează:** Identifică toate interfețele fizice și virtuale disponibile pe stația Linux, precum și starea acestora (`UP`, `DOWN`, `UNKNOWN`).
* **Cum funcționează:** Folosește `ip -o link show` pentru extragerea numelui și stării fiecărei plăci de rețea, alături de `ip -4 addr show` pentru afișarea adreselor IPv4 asociate. Datele sunt formatate tabelar pentru o citire ușoară.

---

### 🔹 Cerința 2 & 3: Administrarea și Validarea strictă a adreselor IPv4 și a Măștilor
* **Ce realizează:** Permite afișarea, adăugarea, ștergerea (cu confirmare) și înlocuirea adreselor IPv4 de pe o interfață selectată, garantând corectitudinea datelor.
* **Algoritmul de validare IP & Mască:**
  * **IP strict:** Verifică existența a exact 4 octeți (0-255) și **blochează zerourile nesemnificative** (ex: respinge `192.168.01.5` sau `10.0.0.05`).
  * **Verificare duplicat:** Controlează dacă IP-ul există deja configurat pe interfață înainte de adăugare.
  * **Mască zecimală & CIDR:** Acceptă formate precum `/24` sau `255.255.255.0`. Pentru forma zecimală, convertește octeții în binar și validează matematic consecutivitatea biților de `1` (evitând măști invalide ca `255.0.255.0`). Calculează și returnează automat prefixul CIDR echivalent.

---

### 🔹 Cerința 4: Configurarea Rutelor și a Gateway-ului
* **Ce realizează:** Oferă control asupra tabelei de rutare a sistemului Linux.
* **Funcționalități:**
  * Afișează tabela de rutare curentă (`ip route show`).
  * Configurează sau înlocuiește Gateway-ul implicit (*Default Gateway*).
  * Șterge ruta implicită la cerere.
  * Adaugă sau șterge rute statice către rețele specifice (ex: `172.16.0.0/16 via 192.168.1.1`).

---

### 🔹 Cerința 5: Diagnosticarea Automată a Conectivității
* **Ce realizează:** Execută un test în cascadă pentru a verifica starea conexiunii la rețea.
* **Pașii de verificare:**
  1. Verifică dacă interfața este activă (`UP`).
  2. Verifică dacă are atribuită o adresă IPv4.
  3. Detectează existența rutei implicite.
  4. Testează cu `ping` răspunsul Gateway-ului local.
  5. Testează conectivitatea WAN prin `ping` la un IP extern (ex: `8.8.8.8`).
  6. Verifică rezoluția de nume DNS (`google.com`) și accesibilitatea destinației finale.

---

### 🔹 Cerința 6: Monitorizarea Conexiunilor și Porturilor Active (`ss`)
* **Ce realizează:** Analizează traficul și sockets-ii activi din sistem folosind utilitarul modern `ss`.
* **Opțiuni oferite:**
  * Afișează porturile TCP aflate în ascultare (`ss -tlnp`).
  * Afișează porturile UDP active (`ss -unap`).
  * Afișează conexiunile TCP stabilite (`ss -tanp state established`).
  * Filtrare interactivă a rezultatelor după un număr de port specific sau numele unui proces (ex: `22`, `80`, `sshd`).

---

### 🔹 Cerința 7: Salvarea și Restaurarea Configurației (Backup & Restore)
* **Ce realizează:** Previne pierderea setărilor prin crearea de salvări structurate ce pot fi re-aplicate automat.
* **Cum funcționează:**
  * **Backup:** Exportă toate adresele IP și rutele curente într-un fișier text din directorul `backup/`, marcat cu timestamp (ex: `config_backup_YYYY-MM-DD_HH-MM-SS.txt`).
  * **Restore:** Citește fișierul salvat, parsează comenzile de tip `ADDR` și `ROUTE` și le re-aplică pe sistem în mod automat, aducând rețeaua la starea salvată anterior.

---

### 🔹 Cerințele 8 & 9 (Suplimentare): DNS Info & Restart Link
* **Cerința 8 (Afișare DNS):** Extrage și afișează rapid serverele DNS active din fișierul de sistem `/etc/resolv.conf`.
* **Cerința 9 (Resetare Interfață):** Execută oprirea temporară (`ip link set dev IFACE down`) și repornirea plăcii de rețea (`up`) pentru rezolvarea rapidă a blocajelor fizice de link.

---

## 📌 Cerințe de Sistem și Rulare

### Cerințe de sistem
* Sistem de operare Linux (Ubuntu / Debian / CentOS etc.).
* Utilitarele `iproute2`, `ss`, `ping`, `bc` și `host`/`nslookup` instalate.
* Privilegii de administrator (`sudo`) pentru modificarea parametrilor de rețea.
