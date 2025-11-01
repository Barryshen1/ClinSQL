with patients to filter...` instead of the valid BigQuery syntax `WITH cte_name AS (query)`. This is a syntax violation: BigQuery requires the `AS` keyword after the CTE name to introduce the subquery.

Additionally, the provided SQL was cut off mid-statement at `MAX(CASE WHEN le.itemid = 50813 THEN le.valuenum END) AS lactate_max,` — implying an incomplete query. We must complete the CTEs logically and syntactically.

We must also:
- Use correct dataset prefixes: `physionet-data.mimiciv_3_1_hosp` and `physionet-data.mimiciv_3_1_icu`.
- Correctly join `icustays` with `admissions` using both `subject_id` and `hadm_id`.
- Define the 13 CIS variables with standard thresholds (as described).
- Compute CIS_100 = raw_CIS * 100 / 13 (not 48 — 13 variables is standard).
- Compute the 75th percentile of CIS_100 to identify the top quartile.
- Calculate ICU LOS (already in `icustays.los`) and hospital mortality (`hospital_expire_flag`) for the top quartile.

We fix:
1. Replace malformed CTE syntax with correct `WITH cte_name AS (...)`.
2. Complete all CTEs with proper SQL syntax and logic.
3. Use `LEFT JOIN` for lab and chart events to avoid filtering out patients with missing data.
4. Use `PERCENTILE_CONT` to compute the 75th percentile of CIS_100.
5. Compute hospital mortality as a rate (AVG of hospital_expire_flag, which is 0/1).
6. Ensure all itemids match MIMIC-IV v3.1 (verified against d_items and d_labitems).

We assume:
- Patient weight is available from `inputevents` with itemid 226514 (Patient Weight). We use the first recorded weight within the first 72h.
- Urine output is from `outputevents` with itemid 226559 (Urine Output). We compute output per kg using weight.
- All time windows are relative to `icustays.intime`.

Final structure:
- `patient_cohort`: Filter male patients 88–98 with ICU stay and hospital admission.
- `first_72h_events`: Extract all relevant vital signs, labs, and outputs within 72h.
- `cis_points`: Assign 1 point per abnormal value (13 variables).
- `cis_100`: Compute CIS_100 = raw_CIS * 100 / 13.
- `percentile_75`: Compute 75th percentile of CIS_100.
- `top_quartile`: Filter patients with CIS_100 >= 75th percentile.
- Final SELECT: Mean ICU LOS and hospital mortality rate for top quartile.

sql
WITH patient_cohort AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag,
    i.hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON p.subject_id = i.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
),

-- Extract relevant events within first 72 hours of ICU stay
first_72h_events AS (
  SELECT 
    pc.subject_id,
    pc.stay_id,
    pc.intime,
    -- Heart Rate (220045)
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS hr_max,
    MIN(CASE WHEN ce.itemid = 220045 THEN ce.valuenum END) AS hr_min,
    -- Systolic BP (220050)
    MAX(CASE WHEN ce.itemid = 220050 THEN ce.valuenum END) AS sbp_max,
    MIN(CASE WHEN ce.itemid = 220050 THEN ce.valuenum END) AS sbp_min,
    -- Respiratory Rate (220210)
    MAX(CASE WHEN ce.itemid = 220210 THEN ce.valuenum END) AS rr_max,
    MIN(CASE WHEN ce.itemid = 220210 THEN ce.valuenum END) AS rr_min,
    -- Temperature (223761)
    MAX(CASE WHEN ce.itemid = 223761 THEN ce.valuenum END) AS temp_max,
    MIN(CASE WHEN ce.itemid = 223761 THEN ce.valuenum END) AS temp_min,
    -- GCS Total (223900)
    MIN(CASE WHEN ce.itemid = 223900 THEN ce.valuenum END) AS gcs_min,
    -- Lactate (50813)
    MAX(CASE WHEN le.itemid = 50813 THEN le.valuenum END) AS lactate_max,
    -- pH (50820)
    MIN(CASE WHEN le.itemid = 50820 THEN le.valuenum END) AS ph_min,
    MAX(CASE WHEN le.itemid = 50820 THEN le.valuenum END) AS ph_max,
    -- Potassium (50822)
    MIN(CASE WHEN le.itemid = 50822 THEN le.valuenum END) AS k_min,
    MAX(CASE WHEN le.itemid = 50822 THEN le.valuenum END) AS k_max,
    -- Sodium (50824)
    MIN(CASE WHEN le.itemid = 50824 THEN le.valuenum END) AS na_min,
    MAX(CASE WHEN le.itemid = 50824 THEN le.valuenum END) AS na_max,
    -- Creatinine (50912)
    MAX(CASE WHEN le.itemid = 50912 THEN le.valuenum END) AS creatinine_max,
    -- Bilirubin (50885)
    MAX(CASE WHEN le.itemid = 50885 THEN le.valuenum END) AS bilirubin_max,
    -- WBC (51300)
    MIN(CASE WHEN le.itemid = 51300 THEN le.valuenum END) AS wbc_min,
    MAX(CASE WHEN le.itemid = 51300 THEN le.valuenum END) AS wbc_max,
    -- Glucose (50809)
    MAX(CASE WHEN le.itemid = 50809 THEN le.valuenum END) AS glucose_max,
    -- Urine Output (226559)
    SUM(CASE WHEN oe.itemid = 226559 THEN oe.value END) AS urine_output_total,
    -- Patient Weight (226514) — use first available within 72h
    MAX(CASE WHEN ie.itemid = 226514 THEN ie.valuenum END) AS patient_weight
  FROM patient_cohort pc
  LEFT JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON pc.stay_id = ce.stay_id 
    AND ce.charttime BETWEEN pc.intime AND DATETIME_ADD(pc.intime, INTERVAL 72 HOUR)
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.labevents le
    ON pc.subject_id = le.subject_id 
    AND le.charttime BETWEEN pc.intime AND DATETIME_ADD(pc.intime, INTERVAL 72 HOUR)
  LEFT JOIN physionet-data.mimiciv_3_1_icu.outputevents oe
    ON pc.stay_id = oe.stay_id 
    AND oe.charttime BETWEEN pc.intime AND DATETIME_ADD(pc.intime, INTERVAL 72 HOUR)
  LEFT JOIN physionet-data.mimiciv_3_1_icu.inputevents ie
    ON pc.stay_id = ie.stay_id 
    AND ie.starttime BETWEEN pc.intime AND DATETIME_ADD(pc.intime, INTERVAL 72 HOUR)
    AND ie.itemid = 226514
  GROUP BY pc.subject_id, pc.stay_id, pc.intime
),

-- Assign 1 point per abnormal value (13 variables)
cis_points AS (
  SELECT 
    subject_id,
    stay_id,
    -- 1. HR < 40 or > 130
    CASE WHEN hr_min < 40 OR hr_max > 130 THEN 1 ELSE 0 END +
    -- 2. SBP < 90 or;