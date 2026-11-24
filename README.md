<div align="center">
  <h1>Pi arro000 flavour install</h1>
  <p>L’ultima versione stabile di Pi e i 21 pacchetti globali di arro000, con un solo script Bash.</p>
</div>

## Installazione

Per **Linux e macOS**. Servono Bash, `curl` e una connessione a Internet. Se manca una versione compatibile di Node.js, l’installer ufficiale propone come installarla.

```bash
curl -fsSLo pi-arro000-install.sh https://raw.githubusercontent.com/arro000/pi-arro000-flavour-install/main/install.sh
# Leggi il file scaricato prima di eseguirlo.
bash pi-arro000-install.sh
```

Accetta l’installazione o la reinstallazione nel menu ufficiale. Se chiede di avviare Pi subito, rispondi **n**: i pacchetti vengono installati dopo. Al termine esegui `pi`; se non è ancora nel `PATH`, usa il percorso mostrato dallo script o riapri il terminale dopo aver accettato la modifica del `PATH`.

## Cosa fa

- Scarica ed esegue l’[installer ufficiale di Pi](https://pi.dev/install.sh), che sceglie l’ultima release stabile disponibile.
- Installa in sequenza i [21 pacchetti npm](install.sh) con `pi install`. I pacchetti non sono vincolati a versioni fisse.
- Mostra un toroide ASCII rotante: la parte piena cresce a ogni passaggio completato. Il menu ufficiale mantiene il controllo del terminale mentre è attivo. Su terminali piccoli o con output reindirizzato lo script usa messaggi di testo.

Lo script si ferma al primo errore e non annulla i passaggi già riusciti. Non copia login, chiavi, sessioni, modelli o configurazioni personali. Alcuni pacchetti possono richiedere configurazioni o strumenti esterni per funzionare. I pacchetti Pi possono eseguire codice: verifica quelli elencati prima di installarli. Per accedere a un provider usa `/login` dentro Pi.

## Verifica locale

```bash
bash -n install.sh
bash test.sh
```

Il test simula il download e le installazioni senza usare la rete o la configurazione reale di Pi. Lo script è sotto licenza [MIT](LICENSE); Pi e i pacchetti mantengono le proprie licenze.
