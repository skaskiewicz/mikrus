#!/bin/bash
#
# KAMIL SKASKIEWICZ - k.skaskiewicz@gmail.com
#
# Skrypt pobiera pliki z kopiami zapasowymi z serwera zdalnego. Na serwer zdalny wgrywa plik kontrolny, który wykorzystuje skrypt delete_old_backup.sh. Gdy plik nie zostanie wgrany - na serwerze zdalnym nie wykona się delete_old_backup.sh. Dodatkowo jest wysyłany plik loga.
# Po wykonaniu pobrania plików z serwera zdalnego, wykonywane jest czyszczenie plików z kopiami zapasowymi na maszynie lokalnej.
# Konfiguracja jest opisana w pliku yaml.dist.
#
#TODO:
# obsługa błędów pobierania: gdy błąd - pominąć etap kasowania
# dodanie parametrów dla:
#   - liczby całkowitej informującej o pozostałym wolnym miejscu

config_file=$1

# Funkcja do logowania komunikatów
log() {
    local timedate
    timedate=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    printf "%s - %s\n" "$timedate" "$1" >>"$LOG_FILE"
}

# Funkcja rekurencyjnie usuwająca pliki z danego katalogu i jego podkatalogów. $snapshot_pattern jest opcjonalne
cleanupRecursively() {
    local directory="$1"
    local recent_dates_or_files="$2"
    local number="$3"
    local snapshot_pattern="$4"

    case $recent_dates_or_files in
    # dni
    days)
        # jeśli $snapshot_pattern jest niepusty - usuwa pliki z danego katalogu i jego podkatalogów
        if [ -n "$snapshot_pattern" ]; then
            find "$directory" -type f -name "$snapshot_pattern*" -mtime "+$number" -delete
        # jeśli $snapshot_pattern jest pusty - usuwa pliki z danego katalogu i jego podkatalogów z pominięciem wzorca nazw $SNAPSHOT_PATTERN
        else
            find "$directory" -type f -not -name "$SNAPSHOT_PATTERN*" -mtime "+$number" -delete
        fi
        ;;
    # godzin
    hours)
        # jeśli $snapshot_pattern jest niepusty - usuwa pliki z danego katalogu i jego podkatalogów
        if [ -n "$snapshot_pattern" ]; then
            find "$directory" -type f -name "$snapshot_pattern*" -mmin "+$(($number * 60 + 1))" -delete
        # jeśli $snapshot_pattern jest pusty - usuwa pliki z danego katalogu i jego podkatalogów z pominięciem wzorca nazw $SNAPSHOT_PATTERN
        else
             find "$directory" -type f -not -name "$SNAPSHOT_PATTERN*" -mmin "+$(($number * 60 + 1))" -delete
        fi
        ;;
    # pliki
    files)
        # jeśli $snapshot_pattern jest niepusty - usuwa pliki z danego katalogu i jego podkatalogów
        if [ -n "$snapshot_pattern" ]; then
            find "$directory" -maxdepth 1 -type f -name "$snapshot_pattern*" -printf "%T@ %p\n" | sort -n | head -n -$number | cut -d ' ' -f 2- | xargs rm -f
        # jeśli $snapshot_pattern jest pusty - usuwa pliki z danego katalogu i jego podkatalogów z pominięciem wzorca nazw $SNAPSHOT_PATTERN
        else
            find "$directory" -maxdepth 1 -type f -not -name "$SNAPSHOT_PATTERN*" -printf "%T@ %p\n" | sort -n | head -n -$number | cut -d ' ' -f 2- | xargs rm -f
        fi
        ;;
    *)
        log "Błąd: Niepoprawna wartość RECENT_DATES_OR_FILES: $recent_dates_or_files"
        log "Dopuszczalne wartości: days, hours, files"
        sendLog
        exit 1
        ;;
    esac

    # Rekurencyjne wywołanie funkcji dla wszystkich podkatalogów w danym katalogu.
    for subdir in "$directory"/*; do
        if [ -d "$subdir" ]; then
            cleanupRecursively "$subdir" "$recent_dates_or_files" "$number" "$snapshot_pattern"
        fi
    done
}

# funkcja wysyłająca plik logu na serwer zdalny, jeśli plik istnieje lokalnie
sendLog(){
    if [ "$BAD_LOG_FILE" = false ]; then
        rsync -e "ssh -p $REMOTE_PORT -i $PRIVATE_KEY" "$LOG_FILE" "$SSH_USERNAME@$REMOTE_ADDRESS:$REMOTE_LOG_PATH" >>/dev/null
    fi
}

# Sprawdzenie czy podano jako parametr ścieżkę do pliku yaml
if [ -z "$config_file" ]; then
    printf "Błąd: Nie podano ścieżki do  pliku konfiguracyjnego"
    exit 1
fi

# Sprawdzenie, czy plik YAML istnieje i jest do odczytu
if [ ! -e "$config_file" ] || [ ! -r "$config_file" ]; then
    printf "Błąd: Plik konfiguracyjny nie istnieje lub nie można go odczytać: %s\n" "$config_file"
    exit 1
fi

# Wczytanie ustawień z pliku YAML
PRIVATE_KEY=$(grep "PRIVATE_KEY:" "$config_file" | awk '{print $2}')
SSH_USERNAME=$(grep "SSH_USERNAME:" "$config_file" | awk '{print $2}')
REMOTE_ADDRESS=$(grep "REMOTE_ADDRESS:" "$config_file" | awk '{print $2}')
REMOTE_PORT=$(grep "REMOTE_PORT:" "$config_file" | awk '{print $2}')
SNAPSHOT_DIRECTORY=$(grep "SNAPSHOT_DIRECTORY:" "$config_file" | awk '{print $2}')
SNAPSHOT_PATTERN=$(grep "SNAPSHOT_PATTERN:" "$config_file" | awk '{print $2}')
OTHER_FILES_DIRECTORY=$(grep "OTHER_FILES_DIRECTORY:" "$config_file" | awk '{print $2}')
DESTINATION_DIRECTORY=$(grep "DESTINATION_DIRECTORY:" "$config_file" | awk '{print $2}')
LOG_FILE=$(grep "LOG_FILE:" "$config_file" | awk '{print $2}')
REMOTE_LOG_PATH=$(grep "REMOTE_LOG_PATH:" "$config_file" | awk '{print $2}')
NUMBER_OF_SNAPSHOTS_TO_KEEP=$(grep "NUMBER_OF_SNAPSHOTS_TO_KEEP:" "$config_file" | awk '{print $2}')
UNIT_OF_SNAPSHOT_NUMBERS=$(grep "UNIT_OF_SNAPSHOT_NUMBERS:" "$config_file" | awk '{print $2}')
NUMBER_OF_OTHER_FILES_TO_KEEP=$(grep "NUMBER_OF_OTHER_FILES_TO_KEEP:" "$config_file" | awk '{print $2}')
UNIT_OF_OTHER_FILES=$(grep "UNIT_OF_OTHER_FILES:" "$config_file" | awk '{print $2}')

# Sprawdzenie czy lokalny plik logu istnieje lub jest do zapisu. Jeśli nie istnieje to utworzenie nowego pliku
BAD_LOG_FILE=false # flag informująca czy zapisywać do pliku logu
if [ ! -f "$LOG_FILE" ]; then
    touch "$LOG_FILE"
elif [ ! -w "$LOG_FILE" ]; then
    printf "Błąd: Podany plik logu (%s) nie istnieje lub nie ma uprawnień do zapisu. Nic nie będzie logowane do pliku.\n" "$LOG_FILE"
    # zmień falgę BAD_LOG_FILE do true - brak logowania do pliku
    BAD_LOG_FILE=true
fi

log "Rozpoczynam nową kopię zapasową..."
sendLog

# Sprawdzenie czy na lokalnje maszynie pozostało miejsce na dysku. ilość zahardkodowana = 5 GB
#TODO: - sparametryzować ilosć wolnego miejsca
avalible_space=$(df -P / | awk '{printf "%.0f\n", $4/1024/1024}' | tail -n +2)
if [ "$avalible_space" -lt "5" ]; then
    if [ "$BAD_LOG_FILE" = false ]; then
        # gdy logowanie do pliku jest dostępne
        log "Uwaga: Pozostało mniej niż 5 GB miejsca na dysku. Przerwanie."
        sendLog
    else
        # gdy logowanie do pliku nie jest dostępne
        printf "Uwaga: Pozostało mniej niż 5 GB miejsca na dysku. Przerwanie.\n"
    fi
    exit 1
fi

# Sprawdznie czy podany klucz prywatny istnieje i jest do odczytu
if [ ! -f "$PRIVATE_KEY" ] || [ ! -r "$PRIVATE_KEY" ]; then
    if [ "$BAD_LOG_FILE" = false ]; then
        # gdy logowanie do pliku jest dostępne
        log "Błąd: Nie udało się odczytać klucza prywatnego: $PRIVATE_KEY"
        sendLog
    else
        # gdy logowanie do pliku nie jest dostępne
        printf "Błąd: Nie udało się odczytać klucza prywatnego: %s\n" "$PRIVATE_KEY"
    fi
    exit 1
fi

# Sprawdzenie czy podany katalog docelowy istnieje i jest do zapisu
if [ ! -d "$DESTINATION_DIRECTORY" ] || [ ! -w "$DESTINATION_DIRECTORY" ]; then
    if [ "$BAD_LOG_FILE" = false ]; then
        # gdy logowanie do pliku jest dostępne
        log "Błąd: Podany katalog docelowy ($DESTINATION_DIRECTORY) nie istnieje lub nie ma uprawnień do zapisu. Przerwanie."
        sendLog
    else
        # gdy logowanie do pliku nie jest dostępne
        printf "Błąd: Podany katalog docelowy (%s) nie istnieje lub nie ma uprawnień do zapisu. Przerwanie.\n" "$DESTINATION_DIRECTORY"
    fi
    exit 1
fi

# Sprawdzenie czy zalogowanie do maszyny zdalnej wykonało się poprawnie
ssh_oputput=$(ssh -p "$REMOTE_PORT" -i "$PRIVATE_KEY" "$SSH_USERNAME@$REMOTE_ADDRESS" "exit" 2>&1)

# Sprawdzenie kodu wyjścia SSH
if [ $? -ne 0 ]; then
    # Wyświetlenie informacji o błędzie
    if [ "$BAD_LOG_FILE" = false ]; then
        # gdy logowanie do pliku jest dostępne
        log "Błąd logowania SSH: $ssh_oputput"
        sendLog
    else
        # gdy logowanie do pliku nie jest dostępne
        printf "Błąd logowania SSH: %s\n" "$ssh_oputput"
    fi
    exit 1
fi

#########################################################
# CZĘŚĆ ODPOWIEDZIALNA ZA POBIERANIE I KASOWANIE PLIKÓW #
#########################################################

# Kontynuacja wykonania skryptu po poprawnym zalogowaniu
if [ "$BAD_LOG_FILE" = false ]; then
    # gdy logowanie do pliku jest dostępne
    log "OK: Zalogowano pomyślnie."
    log "Etap pierwszy - pobranie snapshotów."
    sendLog
else
    # gdy logowanie do pliku nie jest dostępne
    printf "OK Zalogowano pomyślnie."
    printf "Etap pierwszy - pobranie snapshot."
fi
# TODO:
# dopisanie sprawdzenia czy katalog źródłowy i podkatalogi w nim zawarte oraz katalog snapshota istnieje i jest do odczytu

##################################
# ETAP 1 - POBIERANIE SNAPSHOTÓW #
##################################

# Zalogowanie przez SSH do maszyny zdalnej i skopiowanie plików pasujących do wzorca
rsync -e "ssh -p $REMOTE_PORT -i $PRIVATE_KEY" --include="$SNAPSHOT_PATTERN*" --exclude="*" --recursive --info=progress2 --human-readable --times --perms --ignore-existing --backup --suffix=exist "$SSH_USERNAME@$REMOTE_ADDRESS:$SNAPSHOT_DIRECTORY" "$DESTINATION_DIRECTORY" >>/dev/null

#TODO: obsluga błędu pobierania plików. wyświetlenie komunikatu o błędzie

if [ "$BAD_LOG_FILE" = false ]; then
    log "OK: Zakończono etap pierwszy."
    log "Etap drugi - kasowanie starych plików snapshota na maszynie lokalnej z folderu $DESTINATION_DIRECTORY."
    sendLog
else
    printf "OK: Zakończono etap pierwszy."
    printf "Etap drugi - kasowanie starych plików snapshota na maszynie lokalnej z folderu %s.\n" "$DESTINATION_DIRECTORY"
fi

###############################################
# ETAP 2 - KASOWANIE STARYCH PLIKÓW SNAPSHOTA #
###############################################

# Usunięcie najstarszych plików snapshota, pozostawiając tylko tyle ile wskazano w pliku konfiguracyjnym.
# Do poszukiwania wykorzystywany jest parametr DESTINATION_DIRECTORY i w nim są rekurencyjnie poszukiwane pliki o podanym wzorcu SNAPSHOT_PATTERN.
cleanupRecursively "$DESTINATION_DIRECTORY" "$UNIT_OF_SNAPSHOT_NUMBERS" "$NUMBER_OF_SNAPSHOTS_TO_KEEP" "$SNAPSHOT_PATTERN"

if [ "$BAD_LOG_FILE" = false ]; then
    log "OK: Zakończono etap drugi."
    log "Etap trzeci - pobranie pozostałych plików z katalogu $OTHER_FILES_DIRECTORY"
    sendLog
else
    printf "OK: Zakończono etap drugi."
    printf "Etap trzeci - pobranie pozostałych plików z katalogu %s.\n" "$OTHER_FILES_DIRECTORY"
fi

#TODO: obsluga błędu kasowania plików. wyświetlenie komunikatu o błędzie

########################################
# ETAP 3 - Pobranie pozostałych plików #
########################################

# Kopiowanie całej zawartości katalogu OTHER_FILES_DIRECTORY
rsync -e "ssh -p $REMOTE_PORT -i $PRIVATE_KEY" --recursive --info=progress2 --human-readable --times --perms --ignore-existing --backup --suffix=exist "$SSH_USERNAME@$REMOTE_ADDRESS:$OTHER_FILES_DIRECTORY" "$DESTINATION_DIRECTORY" >>/dev/null

#TODO: obsługa błędu pobierania plików. wyświetlenie komunikatu o błędzie

if [ "$BAD_LOG_FILE" = false ]; then
    log "OK: Zakończono etap trzeci - pobranie pozostałych plików z katalogu $OTHER_FILES_DIRECTORY"
    log "Etap czwarty - kasowanie z katalogu $DESTINATION_DIRECTORY plików innych niż snapshot."
    sendLog
else
    printf "Zakończono etap trzeci - pobranie pozostałych plików z katalogu %s\n" "$OTHER_FILES_DIRECTORY"
    printf "Etap czwarty - kasowanie z katalogu %s plików innych niż snapshot.\n" "$DESTINATION_DIRECTORY"
fi

#########################################
# ETAP 4 - KASOWANIE POZOSTAŁYCH PLIKÓW #
#########################################

# Usunięcie najstarszych plików, pozostawiając tylko tyle ile wskazano w pliku konfiguracyjnym.
# Do poszukiwania wykorzystywany jest parametr DESTINATION_DIRECTORY i w nim są rekurencyjnie poszukiwane pliki o podanym wzorcu SNAPSHOT_PATTERN.
for directory in "$DESTINATION_DIRECTORY"/*; do
    cleanupRecursively "$directory" "$UNIT_OF_OTHER_FILES" "$NUMBER_OF_OTHER_FILES_TO_KEEP"
done

if [ "$BAD_LOG_FILE" = false ]; then
    log "OK: Zakończono etap czwarty - kasowanie z katalogu $DESTINATION_DIRECTORY plików innych niż snapshot."
    sendLog
else
    printf "OK: Zakończono etap czwarty - kasowanie z katalogu %s plików innych niż snapshot.\n" "$DESTINATION_DIRECTORY"
fi

#TODO: obsluga błędu kasowania plików. wyświetlenie komunikatu o błędzie

# Plik "ok.txt" do wgrania na serwer zdalny po pełnym sukcesie
if [ "$BAD_LOG_FILE" = false ]; then
    log "Sukces: Zakończono wszystkie etapy."
    sendLog

    # Wgranie pustego pliku "ok.txt" na serwer zdalny
    touch "$DESTINATION_DIRECTORY/ok.txt"
    rsync -e "ssh -p $REMOTE_PORT -i $PRIVATE_KEY" "$DESTINATION_DIRECTORY/ok.txt" "$SSH_USERNAME@$REMOTE_ADDRESS:$REMOTE_LOG_PATH" >>/dev/null
    rm "$DESTINATION_DIRECTORY/ok.txt"  # Usunięcie pliku lokalnie po zakończeniu
else
    # gdy logowanie do pliku nie jest dostępne
    printf "Sukces: Zakończono wszystkie etapy.\n"

    # Wgranie pustego pliku "ok.txt" na serwer zdalny
    touch "$DESTINATION_DIRECTORY/ok.txt"
    rsync -e "ssh -p $REMOTE_PORT -i $PRIVATE_KEY" "$DESTINATION_DIRECTORY/ok.txt" "$SSH_USERNAME@$REMOTE_ADDRESS:$REMOTE_LOG_PATH" >>/dev/null
    rm "$DESTINATION_DIRECTORY/ok.txt"  # Usunięcie pliku lokalnie po zakończeniu
fi