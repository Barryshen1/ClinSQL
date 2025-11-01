with something like `physionet-data.mimiciv_3_1_hosp.table_name` directly in the FROM clause without proper quoting or structure — but in BigQuery, dataset names containing hyphens (`-`) must be enclosed in backticks (`).

BigQuery requires backticks around identifiers (like dataset names) that contain special characters such as hyphens. The dataset name `physionet-data` contains a hyphen, so it must be written as `` `physionet-data` ``.

Additionally, the clinical question asks for:
- A cohort of female ICU patients aged 63–73 with status epilepticus during the first 72 hours of ICU stay.
- For this cohort, compute:
  - Mean and percentiles (P25, P50, P75, P90) of a “vital-instability index” (which is not a standard MIMIC-IV column — we must define it).
  - Compare tachycardia burden, MAP < 65 burden, ICU LOS, and mortality to the general ICU population.

We must define “vital-instability index” — in critical care literature, this is often a composite of heart rate, MAP, and sometimes respiratory rate or other parameters. Since no explicit definition is given, we will define it conservatively as a weighted composite of:
- Tachycardia (HR > 100 bpm) — binary flag
- Hypotension (MAP < 65 mmHg) — binary flag
- We'll compute the proportion of time during the first 72 hours that either condition was present → this becomes the “vital-instability index” per patient.

We'll use:
- `icustays` to get ICU stay timing and link to `patients` for age/gender.
- `chartevents` to extract HR and MAP values during the first 72 hours of ICU stay.
- `d_items` to map itemids for HR and MAP.
- `diagnoses_icd` + `d_icd_diagnoses` to identify status epilepticus (ICD-9: 345.0, 345.1, 345.2, 345.3, 345.4, 345.5, 345.6, 345.7, 345.8, 345.9; ICD-10: G40.5, G41.0, G41.1, G41.2, G41.3, G41.8, G41.9).
- Use `admissions` to link `hadm_id` to `subject_id` for age calculation (using `anchor_age`).
- For comparison group: all ICU patients (general ICU) — we'll compute same metrics for all ICU patients.

We'll structure the query as:
1. Define the status epilepticus cohort (females, 63–73, first 72h of ICU).
2. Compute vital-instability index (proportion of time with HR>100 or MAP<65) for each patient in the cohort during first 72h.
3. Compute percentiles and mean for this index.
4. Compute tachycardia burden (fraction of patients with any tachycardia), MAP<65 burden, LOS, mortality for cohort vs general ICU.

We must use backticks for `physionet-data`.

Also note: `anchor_age` is in `patients` table and represents age at anchor_year — we can use it directly.

We'll use `icustays.intime` as the reference time and filter `chartevents.charttime` to be within `intime` and `intime + 72 hours`.

We'll use `d_items` to find itemids for:
- Heart Rate: 'Heart Rate' (itemid 220045)
- MAP: 'MAP' (itemid 220052)

We'll use `admissions.hospital_expire_flag` for mortality (1 = died in hospital).

We'll use `TIMESTAMP_ADD(intime, INTERVAL 72 HOUR)` for 72-hour window.

We'll use `PERCENTILE_CONT` for percentiles.

We'll use `AVG`, `COUNT`, `SUM` for burden metrics.

We'll use CTEs for clarity.

Final query structure:
- CTE1: Identify eligible patients (females, 63–73, status epilepticus, ICU stay)
- CTE2: Extract vital signs (HR, MAP) during first 72h for these patients
- CTE3: Compute vital-instability index per patient (proportion of time with HR>100 or MAP<65)
- CTE4: Compute cohort metrics (mean, percentiles, burden, LOS, mortality)
- CTE5: Compute general ICU metrics
- Final SELECT: JOIN cohort and general ICU metrics for comparison

We'll avoid any unquoted hyphenated dataset names.

sql
WITH status_epilepticus_patients AS (
  SELECT DISTINCT
    i.subject_id,
    i.stay_id,
    i.intime,
    i.outtime,
    p.anchor_age,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON i.subject_id = d.subject_id AND i.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 63 AND 73
    AND dicd.long_title LIKE '%status epilepticus%'
    AND i.intime IS NOT NULL
),

vital_signs_first_72h AS (
  SELECT
    sep.stay_id,
    ce.charttime,
    ce.valuenum AS hr,
    ce2.valuenum AS map
  FROM status_epilepticus_patients sep
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON sep.stay_id = ce.stay_id
    AND ce.charttime >= sep.intime
    AND ce.charttime <= TIMESTAMP_ADD(sep.intime, INTERVAL 72 HOUR)
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
    AND di.label = 'Heart Rate'
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce2
    ON sep.stay_id = ce2.stay_id
    AND ce2.charttime = ce.charttime
    AND ce2.itemid = 220052  -- MAP
  WHERE ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),

vital_instability AS (
  SELECT
    stay_id,
    COUNT(*) AS total_measurements,
    SUM(CASE WHEN hr > 100 OR map < 65 THEN 1 ELSE 0 END) AS unstable_measurements
  FROM vital_signs_first_72h
  GROUP BY stay_id
),

cohort_metrics AS (
  SELECT
    AVG(CAST(unstable_measurements AS FLOAT64) / total_measurements) AS mean_vital_instability_index,
    PERCENTILE_CONT(CAST(unstable_measurements AS FLOAT64) / total_measurements, 0.25) OVER () AS p25_vital_instability_index,
    PERCENTILE_CONT(CAST(unstable_measurements AS FLOAT64) / total_measurements, 0.50) OVER () AS p50_vital_instability_index,
    PERCENTILE_CONT(CAST(unstable_measurements AS FLOAT64) / total_measurements, 0.75) OVER () AS p75_vital_instability_index,
    PERCENTILE_CONT(CAST(unstable_measurements AS FLOAT64) / total_measurements, 0.90) OVER () AS p90_vital_instability_index,
    SUM(CASE WHEN unstable_measurements > 0 THEN 1 ELSE 0 END) * 1.0 / COUNT(*) AS tachycardia_or_hypotension_burden,
    AVG(TIMESTAMP_DIFF(outtime, intime, HOUR)) AS avg_icu_los_hours,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM vital_instability vi
  JOIN status_epilepticus_patients sep ON vi.stay_id = sep.stay_id
),

general_icu AS (
  SELECT
    AVG(TIMESTAMP_DIFF(outtime, intime, HOUR)) AS avg_icu_los_hours,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    SUM(CASE WHEN hr >;