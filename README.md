This PowerShell utility automates advanced Windows repair using DISM and SFC. It intelligently detects your OS, attempts repairs from the local component store or provided install media, and guides you on obtaining matching Microsoft ISOs when needed. Designed for robustness, it logs all actions and generates a detailed task report, making it an essential tool for maintaining Windows 10, Windows 11, and supported Windows Server versions.

---
## The missing knowledge

**SFC** repairs *Windows system files*  
**DISM** repairs the *component store* that SFC depends on

Think of it like this:

- DISM fixes the warehouse

- SFC fixes the shelves using parts from that warehouse

If the warehouse is corrupted, SFC either fails or “repairs” endlessly without meaningfully improving anything.

That’s why **DISM must run first**.

## Correct order of operations

1. **DISM /CheckHealth**  
   Fast check. Is corruption flagged?

2. **DISM /ScanHealth**  
   Deeper scan. Confirms corruption.

3. **DISM /RestoreHealth**  
   Repairs the component store.

4. **SFC /scannow**  
   Repairs system files *after* the store is clean.

Skipping steps is fine in emergencies, but scripts should be deliberate.

## A clean, admin-safe PowerShell script

This is designed to be readable, log everything, and not pretend magic happened when it didn’t.

## What **/online** actually means in DISM

**/online does NOT mean Internet-connected.**

In DISM language:

- **/online** = *the currently running Windows installation*

- **/image:X:** = *an offline Windows image that is not booted*

That’s it. No Wi-Fi. No repos. No clouds.

If DISM were a surgeon:

- **/online** means “operate on the patient who is awake on the table”

- **/image** means “operate on a patient’s scan while they’re not here”

---## Why people get confused

Because **RestoreHealth** *can* talk to Windows Update, people mentally glue that behavior to `/online`.

But these are **two separate concepts**:

| Concept          | Meaning                          |
| ---------------- | -------------------------------- |
| `/online`        | Target is the running OS         |
| `/restorehealth` | Attempt to repair corruption     |
| Windows Update   | Optional repair *source*         |
| `/source`        | Explicit alternate repair source |
| `/limitaccess`   | Do not contact Windows Update    |

The confusion happens when those get collapsed into one idea.

/online means “repair the currently running Windows installation.”  
It does not mean DISM will use the internet.

If you **do not** specify `/source`, DISM may contact **Windows Update services** to **download missing or corrupted component files** for the *component store* (WinSxS).

When DISM uses Windows Update, it is retrieving known-good component files to repair the Windows component store.  
It is not installing updates or patching the operating system.

## What exactly gets downloaded?

Windows Update (normal use):
“What updates should I install this month?”

Windows Update (DISM use):
“I need the original, factory-approved bolt that belongs right here.”

DISM pulls:

- **Exact-version component payloads**

- Matching the **currently installed Windows build**

- Signed Microsoft binaries only

- Files that belong in **WinSxS**, not `System32` directly

Those files are then used as source material for:

- Component store repair

- Future SFC repairs

## The role of /limitaccess

dism /online /cleanup-image /restorehealth /limitaccess
This tells DISM:

- Do not contact Windows Update

- Use only local sources (or fail)

It is a network behavior flag, not a targeting flag.

## Auto-detect Windows build vs ISO build

The problem this solves

DISM is extremely literal. If you feed it install media that does not match:

- Major version (10 vs 11)

- Build number

- Edition compatibility

…it may fail, or worse, “succeed” without actually fixing corruption.

Most scripts assume “Windows 11 ISO = good enough.” That assumption breaks often.

## What we need to compare

### Running OS (target)

From the live system:

- Version

- Build number

- Edition

### Install media (source)

From the WIM/ESD:

- Image build

- Image edition

- Image index

Only then can we choose a safe source index.

---

# DISM Steps

### 1. Target selection

**`/online`**

DISM locks onto:

- The currently booted Windows image

- The active component store at:

`%SystemRoot%\WinSxS`

### 2. Component store integrity evaluation

**Implicit health scan**

DISM evaluates:

- Component manifests (.mum)

- Component catalog files (.cat)

- Payload presence and hashes

- Servicing metadata consistency

This is deeper than `/checkhealth`, but faster than `/scanhealth`.

Think of it as:

> “Is the blueprint consistent with what’s on disk?”

### 3. Corruption classification

DISM categorizes findings into one of four states:

| State          | Meaning                                 |
| -------------- | --------------------------------------- |
| Healthy        | No corruption detected                  |
| Repairable     | Corruption exists and can be repaired   |
| Non-repairable | Corruption exists but no valid source   |
| Unknown        | Servicing stack failure or interruption |

If **no corruption** is detected, DISM exits early.

### 4. Repair source resolution

If corruption **is detected**, DISM determines **where to get clean payloads**.

Priority order:

1. **Explicit `/source`** (WIM, ESD, folder)

2. **Local component store cache**

3. **Windows Update infrastructure**

4. **Fail**

This decision is automatic unless overridden.

Important nuance:

- Windows Update is only contacted **if needed**

- Network access is not guaranteed or required

### 5. Payload acquisition (if required)

If files are missing or corrupted:

DISM retrieves:

- Exact-version component payloads

- Signed Microsoft binaries

- Matching the installed build and edition

This may involve:

- Reading from install media

- Downloading from Windows Update endpoints

- Validating cryptographic signatures

No cumulative updates are installed.

### 6. Component store repair

DISM performs:

- File replacement inside WinSxS

- Metadata repair

- Manifest re-registration

- Hash validation

It does **not** directly touch:

- `System32`

- User files

- Registry hives outside servicing data

It is repairing the *source of truth*, not the active copies.

### 7. Transaction commit

DISM:

- Commits servicing transactions

- Updates CBS (Component Based Servicing) logs

- Marks operations that require reboot

If a reboot is needed:

- Files are staged

- Pending operations are registered

- No immediate restart is forced

### 8. Final health determination

DISM outputs one of several key messages:

- `No component store corruption detected`

- `The restore operation completed successfully`

- `The component store corruption was repaired`

- `The component store is repairable`

- Or a failure code

This message is the **authoritative verdict** for the component store.

---

## What DISM does NOT do (important)

It does **not**:

- Run SFC

- Repair active system files

- Install Windows updates

- Change OS version or patch level

- Fix third-party drivers

- Repair registry corruption unrelated to servicing

That’s why SFC always comes next.
