with non-null `outtime` (from `icustays`), confirming discharge from ICU.
- **Outcomes**:
  - **30-day mortality**: Death within 30 days of admission. Uses `admissions.deathtime` (in-hospital) or `patients.dod` (post-discharge). Checked via `TIMESTAMP_ADD(admittime, INTERVAL 30 DAY)`.
  - **AKI/ARDS rates**: Defined by ICD codes:
    - AKI: ICD-9 `584*`, ICD-10 `N17*`
    - ARDS: ICD-9 `5185`, ICD-10 `J80`
  - **Composite risk score**: Simplified as `(age≥75) + AKI + ARDS` (each 0/1). Percentiles computed via `APPROX_QUANTILES`.
  - **Median survival among decedents**: Days from admission to death for deceased patients, using precise `deathtime` or date-level `dod`.
- **Key Decisions**:
  - **Age calculation**: Uses anchor-based approximation (standard in MIMIC-IV) since exact DOB is redacted.
  - **ICU transfer**: Requires `icustays.outtime IS NOT NULL` to ensure patient left ICU.
  - **Mortality**: Combines in-hospital (`deathtime`) and post-discharge (`dod`) data for completeness.
  - **AKI/ARDS**: Relies on ICD codes (not lab-based criteria) due to simplicity and problem constraints.
  - **Composite score**: Simplified due to undefined "composite risk score" in query; uses clinically relevant factors (age, AKI, ARDS).
  - **Survival days**: Uses `DATETIME_DIFF` for in-hospital deaths and `DATE_DIFF` for post-discharge (approximate but standard).
- **Edge Cases**:
  - Handles missing AKI/ARDS diagnoses via `COALESCE(MAX(...), 0)`.
  - Excludes non-decedents from survival median via `IF(survival_days IS NOT NULL, ...)`.
  - Uses `APPROX_QUANTILES` for efficient percentile calculation.

sql
WITH base AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    p.dod,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 68 AND 78
),
ich AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('430', '431', '432'))
    OR (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
),
icu AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE outtime IS NOT NULL
),
cohort AS (
  SELECT 
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.deathtime,
    b.dod,
    b.age_at_admission
  FROM base b
  INNER JOIN ich ON b.hadm_id = ich.hadm_id
  INNER JOIN icu ON b.hadm_id = icu.hadm_id
),
outcomes AS (
  SELECT 
    c.*,
    CASE;