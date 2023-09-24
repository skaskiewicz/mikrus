#!/bin/bash
#
# KAMIL SKASKIEWICZ - k.skaskiewicz@gmail.com
#
# Skrypt bash tworzy kopie zapasowe baz danych MySQL z pliku konfiguracyjnego mysql_backup_parameters.yaml.
# Sprawdza dostępność pliku i katalogu z kopiami zapasowymi. Pobiera ustawienia z pliku konfiguracyjnego i konwertuje zmienne.
# Tworzy kopie zapasowe baz danych, pomijając te na liście SKIP_DATABASES. Wyświetla komunikaty o sukcesie
# lub błędzie z narzędziami takimi jak mysqldump, gzip i openssl. Sprawdza, czy pliki kopii zapasowych istnieją i wyświetla komunikat o błędzie, jeśli nie.

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
  dateTime "Błąd: Nie podano ścieżki do  pliku konfiguracyjnego."
  exit 1
fi

# Sprawdź czy plik konfiguracyjny istnieje i jest odczytywalny
if [ ! -e "$config_file" ] || [ ! -r "$config_file" ]; then
  dateTime "Błąd: Plik konfiguracyjny nie istnieje lub nie można go odczytać: mysql_backup_parameters.yaml"
  exit 1
fi

# Pobierz ustawienia z pliku konfiguracyjnego
DB_HOST=$(grep "DB_HOST:" "$config_file" | cut -d':' -f2- | awk '{$1=$1};1')
DB_PORT=$(grep "DB_PORT:" "$config_file" | cut -d':' -f2- | awk '{$1=$1};1')
DB_USER=$(grep "DB_USER:" "$config_file" | cut -d':' -f2- | awk '{$1=$1};1')
DB_PASSWORD=$(grep "DB_PASSWORD:" "$config_file" | cut -d':' -f2- | awk '{$1=$1};1')
BACKUP_DIR=$(grep "BACKUP_DIR:" "$config_file" | cut -d':' -f2- | awk '{$1=$1};1')
SKIP_DATABASES=$(grep "SKIP_DATABASES:" "$config_file" | cut -d':' -f2- | awk '{$1=$1};1')
FILE_PASS=$(grep "FILE_PASS:" "$config_file" | cut -d':' -f2- | awk '{$1=$1};1')
PROTOCOL=$(grep "PROTOCOL:" "$config_file" | cut -d':' -f2- | awk '{$1=$1};1')

# Sprawdź czy katalog z kopiami zapasowymi istnieje i jest zapisywalny
if [ ! -d "$BACKUP_DIR" ] || [ ! -w "$BACKUP_DIR" ]; then
  dateTime "Błąd: Katalog z kopiami zapasowymi nie istnieje lub nie jest dostępny do zapisu: $BACKUP_DIR"
  exit 1
fi

# Kasowanie starych logow tymczasowych
if [ -f "/tmp/mysqldump_error" ]; then
  rm -f /tmp/mysqldump_error
fi
if [ -f "/tmp/mysql_error" ]; then
  rm -f /tmp/mysql_error
fi
if [ -f "/tmp/zip_error" ]; then
  rm -f /tmp/zip_error
fi

# Spróbuj połączyć się z bazą danych i pobrać listę baz danych
if ! databases=$(mysql -h "$DB_HOST" -P "$DB_PORT" --user="$DB_USER" --password="$DB_PASSWORD" --protocol="$PROTOCOL" --silent --skip-column-names -e "SHOW DATABASES;" 2> /tmp/mysql_error); then
  mysql_error=$(</tmp/mysql_error)
  dateTime "Błąd: Nie udało się połączyć z bazą danych lub pobrać listy baz danych. Sprawdź ustawienia hosta, portu, użytkownika i hasła. Komunikat błędu: $mysql_error"
  exit 1
fi

# Konwertuj zmienną SKIP_DATABASES na tablicę
IFS=',' read -ra skip_databases <<< "$SKIP_DATABASES"

if [ -n "$FILE_PASS" ]; then
  ZIP_ARGS=(-P "$FILE_PASS")
fi

# Tworzenie tablicy do przechowywania nazw tworzonych plików
created_backups=()

# Iteruj przez listę baz danych i utwórz kopię zapasową w odpowiednim katalogu
for db in $databases; do
  # Sprawdź czy baza danych należy do listy pomijanych
  skip=0
  for skip_db in "${skip_databases[@]}"; do
    if [[ "$skip_db" == "$db" ]]; then
      skip=1
      break
    fi
  done
  if [[ "$skip" == "0" ]]; then
    # Sprawdź czy katalog dla bazy danych istnieje, a jeśli nie, utwórz go
    if [[ ! -d "$BACKUP_DIR/$db" ]]; then
      mkdir -p "$BACKUP_DIR/$db"
    fi
    dateTime "Tworzenie kopii zapasowej bazy danych: $db"
    backup_file="$BACKUP_DIR/$db/$db-$(date +%Y%m%d-%H%M%S)_encrypted.zip" # Nazwa pliku kopii zapasowej
    if mysqldump -h "$DB_HOST" -P "$DB_PORT" --user="$DB_USER" --password="$DB_PASSWORD" --protocol="$PROTOCOL" "$db" > /tmp/"$db".sql 2> /tmp/mysqldump_error; then
      wait # Czekaj na zakończenie komendy `mysqldump`
      if zip -j -q - /tmp/"$db".sql "${ZIP_ARGS[@]}" > "$backup_file" 2> /tmp/zip_error; then
        rm /tmp/"$db".sql # Usuń plik zrzutu bazy danych
        dateTime "Kopia zapasowa bazy danych $db została utworzona i zaszyfrowana."
        created_backups+=("$backup_file") # Dodanie nazwy pliku do tablicy
      else
        zip_error=$(</tmp/zip_error)
        zip_error=${zip_error//$'\n'/}
        error_message="Błąd: Nie udało się utworzyć kopii zapasowej bazy danych $db."
        if [[ ! -z "$zip_error" ]]; then
          error_message+=" Komunikat błędu zip: $zip_error"
        fi
        dateTime "$error_message"
        rm /tmp/"$db".sql # Usuń plik zrzutu bazy danych
      fi
    else
      mysqldump_error=$(</tmp/mysqldump_error)
      error_message="Błąd: Nie udało się utworzyć zrzutu bazy danych $db. Komunikat błędu: $mysqldump_error"
      dateTime "$error_message"
    fi
  fi
done

# Sprawdź czy kopie zapasowe zostały utworzone
for backup_file in "${created_backups[@]}"; do
  if [ ! -f "$backup_file" ]; then # Sprawdzenie czy plik kopii zapasowej istnieje
    dateTime "Błąd: Nie udało się utworzyć kopii zapasowej: $backup_file"
    status="error"
  fi
done

if [ "$status" == "error" ]; then
  dateTime "Błąd: Proces tworzenia kopii zapasowych zakończony z błędami."
else
  dateTime "Sukces: Proces tworzenia kopii zapasowych zakończony sukcesem."
fi
