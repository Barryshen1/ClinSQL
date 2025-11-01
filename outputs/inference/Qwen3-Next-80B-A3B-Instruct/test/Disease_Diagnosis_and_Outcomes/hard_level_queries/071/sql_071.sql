with `itemid = 223900`)
- MAP (from `chartevents` with `itemid = 220050`)
- FiO2 (from `chartevents` with `itemid = 223835` or `220277`)
- Creatinine (from `labevents` with `itemid = 50912`)
- Bilirubin (from `labevents` with `itemid = 50885`)
- Platelets (from `labevents` with `itemid = 51265`)

We will use the first 24 hours of ICU stay for SOFA calculation (as standard).

We will also fix the BigQuery syntax: use backticks for project/dataset names with hyphens: `physionet-data.mimiciv_3_1_hosp` → already correct, but ensure all references use correct dataset names.

We will compute:
- Median SOFA and IQR for AMI patients
- 90-day mortality rate for AMI patients
- Complication rate (using predefined ICD codes)
- Median LOS for AMI survivors
- Risk percentile: for each AMI patient, the percentile of their SOFA score in the control group’s SOFA distribution (using `PERCENT_RANK()` over control group, then joining back)

We will avoid `PERCENT_RANK()` over the same cohort (which gives 0–1 per row) and instead compute the percentile relative to controls.

Final structure:
- CTEs for AMI and control cohorts (same as before, but without SOFA)
- CTE to calculate SOFA for AMI and control ICU stays (first 24h)
- CTE for complications
- CTE for 90-day mortality flag
- CTE for control SOFA scores (to compute percentiles)
- Final SELECT: aggregate AMI metrics + risk percentile (using control distribution)

sql
WITH ami_diagnoses AS (
  SELECT DISTINCT
    di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.long_title LIKE '%acute myocardial infarction%'
     OR di.icd_code LIKE 'I21%'
     OR di.icd_code LIKE 'I22%'
),

ami_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.gender,
    p.dod,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  JOIN ami_diagnoses am ON a.hadm_id = am.hadm_id
  WHERE p.anchor_age BETWEEN 68 AND 78
    AND p.gender = 'F'
),

control_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.gender,
    p.dod,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY i.intime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.hadm_id = i.hadm_id
  LEFT JOIN ami_diagnoses am ON a.hadm_id = am.hadm_id
  WHERE p.anchor_age BETWEEN 68 AND 78
    AND p.gender = 'F'
    AND am.hadm_id IS NULL
),

-- Calculate SOFA score for first 24h of ICU stay for AMI and control patients
sofa_calc AS (
  SELECT
    p.stay_id,
    p.hadm_id,
    p.subject_id,
    -- GCS component (min of E, V, M)
    MAX(CASE WHEN ce.itemid = 223900 THEN ce.valuenum END) AS gcs_total,
    -- MAP component
    MAX(CASE WHEN ce.itemid = 220050 THEN ce.valuenum END) AS mean_arterial_pressure,
    -- FiO2 component (from chartevents)
    MAX(CASE WHEN ce.itemid IN (223835, 220277) THEN ce.valuenum END) AS fio2,
    -- Creatinine (lab)
    MAX(CASE WHEN le.itemid = 50912 THEN le.valuenum END) AS creatinine,
    -- Bilirubin (lab)
    MAX(CASE WHEN le.itemid = 50885 THEN le.valuenum END) AS bilirubin,
    -- Platelets (lab)
    MAX(CASE WHEN le.itemid = 51265 THEN le.valuenum END) AS platelets
  FROM ami_patients p
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON p.stay_id = ce.stay_id 
    AND ce.charttime BETWEEN p.intime AND DATETIME_ADD(p.intime, INTERVAL 24 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON p.subject_id = le.subject_id 
    AND le.charttime BETWEEN p.intime AND DATETIME_ADD(p.intime, INTERVAL 24 HOUR)
  WHERE p.rn = 1
  GROUP BY p.stay_id, p.hadm_id, p.subject_id

  UNION ALL

  SELECT
    p.stay_id,
    p.hadm_id,
    p.subject_id,
    MAX(CASE WHEN ce.itemid = 223900 THEN ce.valuenum END) AS gcs_total,
    MAX(CASE WHEN ce.itemid = 220050 THEN ce.valuenum END) AS mean_arterial_pressure,
    MAX(CASE WHEN ce.itemid IN (223835, 220277) THEN ce.valuenum END) AS fio2,
    MAX(CASE WHEN le.itemid = 50912 THEN le.valuenum END) AS creatinine,
    MAX(CASE WHEN le.itemid = 50885 THEN le.valuenum END) AS bilirubin,
    MAX(CASE WHEN le.itemid = 51265 THEN le.valuenum END) AS platelets
  FROM control_patients p
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON p.stay_id = ce.stay_id 
    AND ce.charttime BETWEEN p.intime AND DATETIME_ADD(p.intime, INTERVAL 24 HOUR);