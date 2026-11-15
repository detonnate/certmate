# CertMate test plan

Run `./tool/run-tests.sh` with Flutter and Python 3 available. Open
`review.md` inside the latest timestamped results folder for individual
outcomes, failures and source coverage. Use the screenshots to review layout
and interaction states alongside the assertions.

| Workflow | Automated coverage | Next verification |
| --- | --- | --- |
| Jobs | Search, open, cascade deletion, duplicate options, premises dropdown | Full create/edit and persistence after app restart |
| Inspection | Checklist creation and bulk confirmation, locked job controls | Individual checklist editing and long-list navigation |
| Circuits | Preset definitions and creation, linked tests, reference Zs and validation | Manual circuit and test editing, alternate board selection |
| Observations | Serious classification and deletion of dependent photos | Capture, replace, permissions denied and cancelled |
| Reports | PDF generation and validation | Signed report lifecycle, saved PDF reopening and multi-page visual review |
| Settings and backup | Settings navigation, merge and legacy address loading | Native import/export, corrupt files, replace confirmation and recovery |
| Storage | Queued snapshot persistence | Disk-full and write-permission errors |
| Layout | Phone-sized widget screenshots | Small screens, tablets, large text, landscape, platform pickers |

## Android device checks

Use a fresh install or test dataset. Record device model, OS, app version,
expected result and actual result in the run folder, along with screenshots.

1. Create a job and set Premises Type. Close and relaunch the app, then
   confirm the job and selection persisted.
2. Add supply details, a board, a circuit, measurements and a checklist
   result. Confirm validation responds to incomplete and failing data.
3. Deny camera access, retry with permission, attach an image from the
   gallery, then replace and delete it. Check cancellation preserves data.
4. Sign a complete report, confirm it locks, generate a PDF, reopen the
   saved report and share it. Check the pages and verify the recipient opens it.
5. Export a backup. On a test dataset, exercise both merge and replace and
   verify circuit tests and photos still belong to the correct records.

## Use results to refine the app

Reproduce an issue with the smallest fixture that shows it. Add an assertion
for the expected behaviour, confirm the case fails, make the app change, and
rerun the suite. Use before-and-after screenshots for visible changes and
keep both run folders for review.
