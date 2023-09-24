#!/bin/bash
#
# KAMIL SKASKIEWICZ - k.skaskiewicz@gmail.com
#
# Skrypt bash tworzy kopie zapasowe wskazanych katalogów z pliku konfiguracyjnego backup_parameters.yaml.
# Sprawdza dostępność pliku i katalogu z kopiami zapasowymi. Pobiera ustawienia z pliku konfiguracyjnego i konwertuje zmienne.
# Tworzy kopie zapasowe katalogów wraz z możiowścią pomijania katalogów i plików, które są wymienione na liście EXCLUDE_DIRS i EXCLUDE_EXT.

config_file=$1

# funkcja generująca czas i komunikat.
dateTime() {
  local timedate
  timedate=$(date '+%Y-%m-%d %H:%M:%S.%3N')
  printf "%s - %s\n" "$timedate" "$1"
}

dateTime "Rozpoczynam nową kopię zapasową..."

# Sprawdzenie czy podano jako parametr ścieżkę do pliku yaml
if [ -z "$config_file" ]; then
  dateTime "Błąd: Nie podano ścieżki do  pliku konfiguracyjnego"
  exit 1
fi

# Sprawdzenie, czy plik YAML istnieje i jest do odczytu
if [ ! -e "$config_file" ] || [ ! -r "$config_file" ]; then
  dateTime "Błąd: Plik z ustawieniami nie istnieje lub nie można go odczytać: $config_file"
  exit 1
fi

# wczytanie ustawień z pliku YAML
BACKUP_DIRS=$(grep "BACKUP_DIR:" "$config_file" | cut -d':' -f2- | awk '{$1=$1};1')
IFS=',' read -r -a BACKUP_DIRS_ARRAY <<< "$BACKUP_DIRS"
EXCLUDE_DIRS=$(grep "EXCLUDE_DIRS:" "$config_file" | cut -d':' -f2- | tr -d ' ')
IFS=',' read -r -a EXCLUDE_DIRS_ARRAY <<< "$EXCLUDE_DIRS"
EXCLUDE_EXT=$(grep "EXCLUDE_EXT:" "$config_file" | cut -d':' -f2- | tr -d ' ')
IFS=',' read -r -a EXCLUDE_EXT_ARRAY <<< "$EXCLUDE_EXT"
ZIP_PASSWORD=$(grep "ZIP_PASSWORD:" "$config_file" | cut -d':' -f2- | awk '{$1=$1};1')
DESTINATION_DIR=$(grep "DESTINATION_DIR:" "$config_file" | cut -d':' -f2- | awk '{$1=$1};1')

# Sprawdzenie, czy podany katalog docelowy istnieje i jest do zapisu
if [ ! -d "$DESTINATION_DIR" ] || [ ! -w "$DESTINATION_DIR" ]; then
  dateTime "Błąd: Podany katalog docelowy ($DESTINATION_DIR) nie istnieje lub nie ma uprawnień do zapisu."
  exit 1
fi

# Funkcja do tworzenia kopii zapasowych
createBackup() {
  local backup_pair="$1"
  local backup_dir="${backup_pair%|*}"
  local backup_name="${backup_pair#*|}"
  local backup_filename
  backup_filename="$(date +"%Y%m%d-%H%M%S").zip"
  local backup_path="$DESTINATION_DIR/$backup_name/$backup_filename"
  local ZIP_ARGS

  # Kasowanie starych logów tymczasowych
  if [ -f "/tmp/zip_error" ]; then
    rm -f /tmp/zip_error
  fi

  # Sprawdzenie, czy wszystkie podkatalogi w katalogu źródłowym są dostępne do odczytu
  find "$(readlink -f "$backup_dir")" -type d ! -readable -print | while read -r dir; do
    dateTime "Błąd: Katalog $dir nie jest dostępny do odczytu."
    return 1
  done

  # Sprawdzenie, czy katalog docelowy istnieje i jest do zapisu
  if [ ! -d "$DESTINATION_DIR" ] || [ ! -w "$DESTINATION_DIR" ]; then
    dateTime "Błąd: Podany katalog docelowy ($DESTINATION_DIR) nie istnieje lub nie ma uprawnień do zapisu."
    return 1
  fi

  # Sprawdzenie, czy katalog $DESTINATION_DIR/$backup_name istnieje, a jeśli nie, to utworzenie go
  if [ ! -d "$DESTINATION_DIR/$backup_name" ]; then
    mkdir -p "$DESTINATION_DIR/$backup_name" || {
      dateTime "Błąd: Nie można utworzyć katalogu kopii zapasowej o nazwie ($backup_name)"
      return 1
    }
  fi

  # Dodanie opcji z hasłem do polecenia zip
  if [ -n "$ZIP_PASSWORD" ]; then
    ZIP_ARGS+=(-P "$ZIP_PASSWORD")
  fi

  # Dodanie opcji wykluczania katalogów
  if [ "${#EXCLUDE_DIRS_ARRAY[@]}" -gt 0 ]; then
    for dir in "${EXCLUDE_DIRS_ARRAY[@]}"; do
      ZIP_ARGS+=(-x "$dir/*")
    done
  fi

  # Dodanie opcji wykluczania plików o określonych rozszerzeniach
  if [ "${#EXCLUDE_EXT_ARRAY[@]}" -gt 0 ]; then
    for ext in "${EXCLUDE_EXT_ARRAY[@]}"; do
      ZIP_ARGS+=(-x "*.$ext")
    done
  fi

  # Wywołanie polecenia zip do tworzenia archiwum
  if ! zip -r -y -q "$backup_path" "$backup_dir" "${ZIP_ARGS[@]}" 2  > /tmp/zip_error; then
    zip_error=$(</tmp/zip_error)
    zip_error=${zip_error//$'\n'/}
    dateTime "Błąd: Tworzenie pliku backupu dla katalogu $backup_dir nie powiodło się. Błąd: $zip_error"
    return 1
  fi

  # Sprawdzenie, czy plik backupu został utworzony
  if [ -e "$backup_path" ]; then
    dateTime "OK: Plik backupu dla katalogu $backup_dir został utworzony: $backup_path"
    return 0
  else
    dateTime "Błąd: Tworzenie pliku backupu dla katalogu $backup_dir nie powiodło się."
    return 1
  fi
}

# Iteracja po wszystkich katalogach BACKUP_DIRS_ARRAY i wykonanie kopii zapasowych
for backup_pair in "${BACKUP_DIRS_ARRAY[@]}"; do
  # Sprawdzenie, czy podana para katalog-nazwa jest poprawna
  if [[ "$backup_pair" != *\|* ]]; then
    dateTime "Błąd: Niepoprawna para katalog-nazwa: $backup_pair. Poprawny format to: /sciezka/do/katalogu|nazwa"
    continue
  fi

  # Podzielenie pary na katalog i nazwę
  createBackup "$backup_pair"
done

dateTime "Sukces: Proces tworzenia kopii zapasowych zakończony sukcesem."