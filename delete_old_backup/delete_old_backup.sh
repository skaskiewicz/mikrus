#!/bin/bash
#
# KAMIL SKASKIEWICZ - k.skaskiewicz@gmail.com
#
# Skrypt bash kasujący pliki z kopiami zapasowymi, rekurencyjnie przechodząc przez katalogi podane w pliku konfiguracyjnym
#

config_file=$1

# Funkcja generująca czas i komunikat.
dateTime() {
  local timedate
  timedate=$(date '+%Y-%m-%d %H:%M:%S.%3N')
  printf "%s - %s\n" "$timedate" "$1"
}

# Funkcja rekurencyjnie usuwająca pliki z danego katalogu i jego podkatalogów.
cleanupRecursively() {
  local directory="$1"
  local recent_dates_or_files="$2"
  local number="$3"

  case $recent_dates_or_files in
    days)
      find "$directory" -type f -mtime "+$number" -delete
      ;;
    hours)
      find "$directory" -type f -mmin "+$(($number*60+1))" -delete
      ;;
    files)
      find "$directory" -maxdepth 1 -type f -printf "%T@ %p\n" | sort -n | head -n -$number | cut -d ' ' -f 2- | xargs rm -f
      ;;
    *)
      dateTime "Błąd: Niepoprawna wartość RECENT_DATES_OR_FILES: $recent_dates_or_files" 
      dateTime "Dopuszczalne wartości: days, hours, files"
      exit 1
      ;;
  esac

  # Rekurencyjne wywołanie funkcji dla wszystkich podkatalogów w danym katalogu.
  for subdir in "$directory"/*; do
    if [ -d "$subdir" ]; then
      cleanupRecursively "$subdir" "$recent_dates_or_files" "$number"
    fi
  done
}

dateTime "Rozpoczynam kasowanie starych kopii zapasowych..."

# Sprawdzenie czy podano jako parametr ścieżkę do pliku yaml
if [ -z "$config_file" ]; then
  dateTime "Błąd: Nie podano ścieżki do  pliku konfiguracyjnego."
  exit 1
fi

# Sprawdzenie, czy plik YAML istnieje i jest do odczytu
if [ ! -e "$config_file" ] || [ ! -r "$config_file" ]; then
  dateTime "Błąd: Plik konfiguracyjny nie istnieje lub nie można go odczytać: $config_file"
  exit 1
fi

# Wczytanie ustawień z pliku YAML
# RECENT_DATES_OR_FILES przyjumje wartości: days, hours, files
RECENT_DATES_OR_FILES=$(grep "RECENT_DATES_OR_FILES:" "$config_file" | awk '{print $2}')
# NUMBER przyjumje wartości: liczba całkowita, która określa ile plików, godzin lub dat ma być zachowanych
NUMBER=$(grep "NUMBER:" "$config_file" | awk '{print $2}')
# DIRECTORY_TO_CLEANUP przyjumje wartości: ścieżka bezwzględna do katalogu, który ma być czyszczony, można podać kilka ścieżek oddzielonych przecinkiem
IFS=',' read -r -a DIRECTORY_TO_CLEANUP <<< "$(grep "DIRECTORY_TO_CLEANUP:" "$config_file" | awk '{print $2}' | sed 's/[][]//g')"
PATH_TO_CONTROL_FILE=$(grep "PATH_TO_CONTROL_FILE:" "$config_file" | awk '{print $2}')

# Sprawdzenie czy istnieje plik "ok.txt" w ścieżce podanej w PATH_TO_CONTROL_FILE
if [ -n "$PATH_TO_CONTROL_FILE" ] && [ ! -f "$PATH_TO_CONTROL_FILE/ok.txt" ]; then
  dateTime "Błąd: Nie znaleziono kontrolnego pliku 'ok.txt' w ścieżce $PATH_TO_CONTROL_FILE. Przyczyna: skrypt kopia_from_mikrus nie został uruchomiony lub jego wykonywanie zakończyło się błędem. Sprawdź odpowiednie logi."
  exit 1
fi

# Kasownie pliku kontrolnego, tak aby przy następnmym wykonaniu skryptu kopia_from_mikrus można było go przesłać lub nie, w zależności czy skrypt zakończył się sukcesem
rm -f "$PATH_TO_CONTROL_FILE/ok.txt"

# Sprawdzenie czy podano poprawną wartość dla RECENT_DATES_OR_FILES
if [ "$RECENT_DATES_OR_FILES" != "days" ] && [ "$RECENT_DATES_OR_FILES" != "hours" ] && [ "$RECENT_DATES_OR_FILES" != "files" ]; then
  dateTime "Błąd: Niepoprawna wartość RECENT_DATES_OR_FILES: $RECENT_DATES_OR_FILES"
  dateTime "Dopuszczalne wartości: days, hours, files"
  exit 1
fi

# Sprawdzenie czy podano poprawną wartość dla NUMBER
if ! [[ "$NUMBER" =~ ^[0-9]+$ ]]; then
  dateTime "Błąd: Niepoprawna wartość NUMBER: $NUMBER"
  dateTime "Dopuszczalne wartości: liczba całkowita"
  exit 1
fi

# Pętla po wszystkich folderach, które mają być czyszczone i rekurencyjne usuwanie starych plików.
for directory in "${DIRECTORY_TO_CLEANUP[@]}"; do
  if [ ! -d "$directory" ] || [ ! -r "$directory" ] || [ ! -w "$directory" ]; then
    dateTime "Błąd: Folder nie istnieje lub nie można go odczytać lub zapisać: $directory"
    dateTime "Sprawdź czy podałeś poprawną ścieżkę do folderu."
    continue
  fi

  cleanupRecursively "$directory" "$RECENT_DATES_OR_FILES" "$NUMBER"
done

dateTime "Sukces: Kasowanie starych kopii zapasowych zakończony sukcesem."
