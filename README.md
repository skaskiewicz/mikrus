
# Mikrus

Repozytorium zawiera skrypty, które wykorzystuję do obsługi generowania i zarządzania kopiami bezpieczeństwa. Nie są specjalnie wyszukane ale spełniają swoje zadanie.


## Deployment

Aby uruchomić wystarczy pobrać repo. Skonfigurować plik yaml według opisu z ymal.dist. Dodać ewentualnie do crona, opcjonalnie wskazując miejsce zapisu logu. Ponieważ dla każdego kroku operacji jest generowana informacja wraz z datą i czasem.

```bash
  git clone https://github.com/skaskiewicz/mikrus.git
```


## Usage/Examples
Wszystkie skrypty, oprócz 'kopia_from_mikrus.sh', należy wykonywać z poziomu maszyny, której kopie chcemy tworzyć. 
'kopia_from_mikrus.sh' należy uruchamiać na maszynie (np. własny laptop lub inny serwer VPS), która ma pobierać kopie z maszyny, którą chcemy zabezpieczyć.

przykład pliku konfiguracyjnego dla skryptu 'mysql_backup.sh':

```yaml
DB_HOST: localhost
DB_PORT: 3306
DB_USER: user
DB_PASSWORD: user_pass
BACKUP_DIR: /my/backup/databases
SKIP_DATABASES: pomijana_baza_danych,information_schema,performance_schema
FILE_PASS: haslo_szyfrowania_pliku_zip
PROTOCOL: socket
```

przykład wywołania skryptu wraz z logowaniem do pliku
```bash
/home/user/git/mikrus/mysql/mysql_backup.sh /home/user/git/mikrus/mysql/mysql_backup_parameters.yaml
 >> /var/log/mysql_backup.log 2>&1
```


## License

[GNU General Public License v3.0](https://github.com/skaskiewicz/mikrus/blob/master/LICENSE)
