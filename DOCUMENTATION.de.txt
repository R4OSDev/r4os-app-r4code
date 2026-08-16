R4CODE und R4BUILD
=====================

R4CODE ist die interne R4OS-IDE. Das Paket liegt unter:

  C:\SOFTWARE\R4CODE\R4CODE.R4X
  C:\SOFTWARE\R4CODE\R4BUILD.R4X
  C:\SOFTWARE\R4CODE\R4PACK.R4X

Der inside-R4OS-C-Compiler liegt im SDK unter:

  C:\R4OS\SDK\Toolchains\C\bin\R4CC.R4X

Aktueller Projektvertrag
------------------------

Seit 0.58.33 ist `module.R4MF` auch fuer R4CODE und R4BUILD die einzige
Projekt-, Build- und Zielwahrheit. R4CODE erstellt und oeffnet direkt:

  module.R4MF
  src\main.c

Das Manifest enthaelt R4MF v2 mit NAME, LANGUAGE, SOURCE, ENTRY_MODE,
APP_CLASS, TARGET, IMAGE_SCOPE und den geordneten IMPORT-Zeilen. Buildprofil,
R4XStart-Export, feste Metadaten und das lokale Artefakt `out\<NAME>.R4X`
werden abgeleitet. R4CODE speichert keine Kopie dieser Felder in einer
Workspace- oder Editorzustandsdatei.

Die installierten C-Vorlagen liegen unter:

  C:\R4OS\SDK\Templates\R4OS\R4X_C_Console
  C:\R4OS\SDK\Templates\R4OS\R4X_C_Desktop_OK

Jede Vorlage besitzt `module.R4MF.template` und `src\main.c.template`.
`template.ini` beschreibt nur die Vorlagenauswahl und dupliziert keine
Manifestfelder.

R4BUILD
-------

R4BUILD verwendet denselben SDK-Parser und denselben kanonischen Planrenderer
wie das Hostwerkzeug ModuleCatalog:

  R4BUILD.R4X VALIDATE <Pfad\module.R4MF>
  R4BUILD.R4X PLAN <Pfad\module.R4MF>
  R4BUILD.R4X BUILD <Pfad\module.R4MF>

`VALIDATE` prueft den Current-only-Vertrag und die Quellen. `PLAN` gibt den
umgebungsneutralen `R4MF_PLAN=1`-Block aus und baut nichts. ModuleCatalog
erzeugt bytegleich denselben Block mit:

  module-catalog contract-plan --manifest <Pfad\module.R4MF>

`BUILD` prueft danach die lokale Compilerfaehigkeit und schreibt das Ergebnis
nach `out\<NAME>.R4X`. Der aktuelle inside-R4OS-Compiler unterstuetzt genau
ein C-Quellfile fuer die App-Profile console und desktop. Zig, Services,
Low-Level-Einstiege, mehrere C-Quellen oder nicht vom Packer abbildbare
Importmengen liefern einen klaren Capabilityfehler. Es gibt keinen Rueckfall
auf Host-Build, R4CodePad, vorgebaute Artefakte oder ein anderes Projektformat.
R4CC akzeptiert fuer beide Profile ausschliesslich den aktuellen C-App-Einstieg
`r4_app_main(R4App*)`; der historische rohe Console-Einstieg ist kein
Compilerfallback mehr.

Historische R4CP-Dateien
------------------------

`.R4CP` ist kein Buildvertrag mehr. R4CODE zeigt beim Oeffnen den Hinweis auf
den expliziten Einmalkonverter:

  R4BUILD.R4X CONVERT <Altprojekt.R4CP> <Ziel\module.R4MF>

Der Konverter liest R4CP nur in diesem Befehl, bewahrt Modulname, Sprache,
Quellenreihenfolge, Imports und TARGET, setzt den sicheren Image-Scope `none`
und schreibt die neue Datei ueber eine temporaere Datei plus Rename. Die
Quelle wird nie ersetzt. Ein bytegleich vorhandenes Ziel ist ein No-op; ein
abweichendes Ziel oder ein Fehler bleibt ohne Aenderung der Quelle bestehen.

Selftests
---------

`R4BUILD.R4X /SELFTEST` erzeugt C-Console- und C-Desktop-R4MF-Projekte,
validiert und plant beide, baut ihre Artefakte, prueft einen Zig-
Capabilityfehler und den idempotenten R4CP-Einmalkonverter samt Fehlerfall.

`R4CODE.R4X /SELFTEST` erzeugt dieselben beiden Projektklassen aus den
installierten R4MF-Templates, laesst VALIDATE, PLAN und BUILD durch R4BUILD
laufen und startet die erzeugten Console-/Desktop-Artefakte. Der Test nutzt
weder R4CodePad noch DevTools, Build.bat oder einen Hostcompiler.

Seit 0.58.30 sind R4CODE, R4BUILD, R4PACK und R4CC vier eigenstaendige
R4MF-v2-Module. Gemeinsame Compiler-/Packer-Cores liegen einmal unter
`Shared\` und werden ueber deklarierte ZIG_MODULE-Aliase eingebunden;
PACKAGE=R4CODE ist ausschliesslich organisatorisch.
