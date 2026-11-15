# CertMate EICR for Flutter

The Flutter app lives alongside the original Swift project. It stores jobs locally and includes supply details, distribution boards, circuits and tests, inspection schedules, observations and photos, signatures, and PDF preview, printing, and sharing.

## User documentation

[CertMate EICR user guide](docs/user-guide.md)

## Run

Install Flutter stable and the toolchain for your target. From this directory run:

```sh
flutter pub get
flutter devices
flutter run -d <device-id>
```

The project includes iOS, Android, and macOS runners. Configure your own signing and application identifiers before distributing it.

## Move jobs from Swift

Export a JSON backup in the Swift app. In Flutter, open **Settings → Import backup** and select the file. Choose Merge to keep existing records when identifiers match, or Replace to restore the selected backup in full. The Swift backup omits supply details, the separate company profile, and saved PDF files. Those records need to be entered or transferred separately. Reports can be regenerated from the imported data.

The Flutter report uses a new PDF layout. It retains the checklist data and validation rules from the Swift project, with validation continuing through later sections even if supply details are missing. The Flutter app uses local storage and JSON backups. The Reports tab opens the saved PDF snapshot. Generate a new PDF from the job to update it.

## Swift workflow comparison

| Swift workflow | Flutter |
| --- | --- |
| Jobs and company profile | Search, create, edit, delete, and apply the saved profile to an existing draft |
| Report details | EICR Wizard, assessment, validation, and signature |
| Inspection records | Supply, distribution boards, circuits and tests, checklist progress and bulk marking, observations and photo replacement |
| Circuit setup | Standard Domestic, Small Flat, and Larger House builder plus individual presets |
| Duplication | Job details, selectable record groups, and optional clearing of test readings |
| Reports and backup | Save and reopen PDF snapshots, export and share PDFs, and merge or replace backups |

The Flutter PDF uses a different layout. CloudKit and direct SwiftData migration remain outside the Flutter implementation. Android and iOS device verification remains pending.

## Checks

```sh
flutter analyze
flutter test
```

## Timestamped test runs

Run `./tool/run-tests.sh` from this directory. Set `FLUTTER_BIN` to a
Flutter executable if Flutter is outside your PATH. Each run creates a new
folder under `test-results/` with a UTC timestamp. Start with `summary.txt`
for exit codes and `tests.txt` for test names and results. The folder also
contains each command's stdout and stderr, Flutter's machine-readable test
events in `tests.stdout`, LCOV line coverage in `lcov.info`, and PNG captures of selected widget-test
states in `screenshots/`. The PNGs are rendered by the Flutter test runner.

The suite runs locally with simulated widgets and temporary storage.
On a physical Android device, also check camera and gallery permissions,
PDF viewing and sharing, backup file picking, and persistence after restart.
