# Manual integration checklist

## Cloud-only Photos transfer progress

**Device prerequisite:** Sign into iCloud Photos on a physical device and select a known image whose full-size original is cloud-only (download it only through the picker during this check).

1. Open the image picker and select the cloud-only image. Confirm the attachment UI reports progress values between 0 and 1 while Photos transfers the `.current` representation.
2. Cancel while an intermediate value is visible. Confirm transfer stops, no terminal completion is shown, and no attachment draft remains.
3. Repeat without cancelling. Confirm completion reaches 1 only after the imported draft exists.
4. Compare the persisted draft's bytes with the file supplied by the picker callback using a SHA-256 digest. They must match exactly.

This acceptance check is documented now because it covers the Task 5 importer repair. The user-facing attachment picker/transfer-progress UI is scheduled for Task 13; execute the case when that target is available.
