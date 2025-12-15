# cuesplit.sh
Splits FLAC-encoded audio CD images of your legally owned CDs using CUE metadata.
Sanitizes output filenames to comply with VFAT restrictions, and Peugeot 208 stock audio quirk (no dots allowed in filenames, except the extension delimeter).

### Pre-requisites
- cuetools
- shntool

### Usage example
```
user@rpi /mnt/storage/Laibach - Kapital
 % ls -1
'Laibach - Kapital.cue'
'Laibach - Kapital.flac'
'Laibach - Kapital.log'
art

user@rpi /mnt/storage/Laibach - Kapital
 % cuesplit.sh --temp-dir /mnt/storage/tmp --output /tmp/flash
[*] Scanning under: .
[*] Processing:
[*]   Audio: ./Laibach - Kapital.flac
[*]   Cue:   ./Laibach - Kapital.cue
[*]   Type:  flac
[*]   Output: /tmp/flash/Laibach - 1992 - Kapital
[*]   Temp:   /mnt/storage/tmp/cuesplit.JBQi8M
[*]   Splitting (lossless)…
shnsplit: warning: file 1 will be too short to be burned
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/00 Laibach - pregap.flac] (0:00.15) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/01 Laibach - Decade Null.flac] (2:55.50) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/02 Laibach - Everlasting In Union.flac] (4:09.50) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/03 Laibach - Illumination.flac] (3:58.65) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/04 Laibach - Le Privilege Des Morts.flac] (5:34.72) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/05 Laibach - Codex Durex.flac] (3:04.40) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/06 Laibach - Hymn To The Black Sun.flac] (5:31.55) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/07 Laibach - Young Europa Pts 1-10.flac] (6:22.13) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/08 Laibach - The Hunter's Funeral Procession.flac] (5:33.47) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/09 Laibach - White Law.flac] (4:23.05) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/10 Laibach - Wirtshaft Ist Tot.flac] (7:12.00) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/11 Laibach - Torso.flac] (4:15.45) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/12 Laibach - Entartete Welt.flac] (8:23.63) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/13 Laibach - Kinderreich.flac] (4:08.62) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/14 Laibach - Sponsored By Mars.flac] (5:37.08) : 100% OK
Splitting [./Laibach - Kapital.flac] (78:40.35) --> [/mnt/storage/tmp/cuesplit.JBQi8M/15 Laibach - Regime Of Coincidence, State Of Gravity.flac] (7:28.45) : 100% OK
[*] Done.\n

 % ls -1 /tmp/flash/Laibach\ -\ 1992\ -\ Kapital
'01 Laibach - Decade Null.flac'
'02 Laibach - Everlasting In Union.flac'
'03 Laibach - Illumination.flac'
'04 Laibach - Le Privilege Des Morts.flac'
'05 Laibach - Codex Durex.flac'
'06 Laibach - Hymn To The Black Sun.flac'
'07 Laibach - Young Europa Pts 1-10.flac'
"08 Laibach - The Hunter's Funeral Procession.flac"
'09 Laibach - White Law.flac'
'10 Laibach - Wirtshaft Ist Tot.flac'
'11 Laibach - Torso.flac'
'12 Laibach - Entartete Welt.flac'
'13 Laibach - Kinderreich.flac'
'14 Laibach - Sponsored By Mars.flac'
'15 Laibach - Regime Of Coincidence, State Of Gravity.flac'
```

### Misc notes
Building shntool from the source on the Raspberry PI
```
wget http://shnutils.freeshell.org/shntool/dist/src/shntool-3.0.10.tar.gz
sha256sum -b shntool-3.0.10.tar.gz
74302eac477ca08fb2b42b9f154cc870593aec8beab308676e4373a5e4ca2102 *shntool-3.0.10.tar.gz
tar -xzf shntool-3.0.10.tar.gz && cd shntool-3.0.10
./configure --build=aarch64-unknown-linux-gnu
make
```
