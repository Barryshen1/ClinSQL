with intracranial hemorrhage (ICH)
WITH patients_ich AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.deathtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag 
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 69 AND 79
    AND (
      (diag.icd_version = 9 AND diag.icd_code IN ('430', '431'))
      OR (diag.icd_version = 10 AND diag.icd_code IN ('I60', 'I61', 'I621'))
    )
    AND a.admission_type NOT IN ('AMBULATORY OBSERVATION', 'OBSERVATION')
),
-- Count abnormal lab events in the first 24 hours of admission
abnormal_labs AS (
  SELECT le.hadm_id, COUNT(*) AS abnormal_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN patients_ich p ON le.hadm_id = p.hadm_id
  WHERE le.charttime >= p.admittime 
    AND le.charttime < DATETIME_ADD(p.admittime, INTERVAL 1 DAY)
    AND le.flag = 'abnormal'
  GROUP BY le.hadm_id
),
-- Identify major complications: mechanical ventilation, vasopressors, dialysis
complications AS (
  -- Mechanical ventilation from procedureevents
  SELECT DISTINCT pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  JOIN patients_ich p ON pe.hadm_id = p.hadm_id
  WHERE LOWER(di.label) LIKE '%ventilator%'
    AND pe.starttime >= p.admittime 
    AND pe.starttime < COALESCE(p.dischtime, '9999-12-31')
  UNION DISTINCT
  -- Vasopressors: norepinephrine, epinephrine, dopamine, vasopressin
  SELECT DISTINCT ie.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` ie
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ie.itemid = di.itemid
  JOIN patients_ich p ON ie.hadm_id = p.hadm_id
  WHERE LOWER(di.label) IN ('norepinephrine', 'epinephrine', 'dopamine', 'vasopressin')
    AND ie.starttime >= p.admittime 
    AND ie.starttime < COALESCE(p.dischtime, '9999-12-31')
  UNION DISTINCT
  -- Dialysis from procedureevents
  SELECT DISTINCT pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  JOIN patients_ich p ON pe.hadm_id = p.hadm_id
  WHERE LOWER(di.label) LIKE '%dialysis%'
    AND pe.starttime >= p.admittime 
    AND pe.starttime < COALESCE(p.dischtime, '9999-12-31')
),
-- Combine data: add risk score, complications, and mortality
cohort AS (
  SELECT 
    p.hadm_id,
    COALESCE(al.abnormal_lab_count, 0) AS risk_score,
    CASE WHEN c.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS had_complication,
    CASE WHEN p.deathtime IS NOT NULL AND DATETIME_DIFF(p.deathtime, p.admittime, DAY) <= 30 THEN 1 ELSE 0 END AS died_within_30d,
    DATETIME_DIFF(p.dischtime, p.admittime, HOUR) / 24.0 AS los_days
  FROM patients_ich p
  LEFT JOIN abnormal_labs al ON p.hadm_id = al.hadm_id
  LEFT JOIN complications c ON p.hadm_id = c.hadm_id
),
-- Assign quintiles based on risk score
quintiles AS (
  SELECT *,
    NTILE(5) OVER (ORDER BY risk_score) AS risk_quintile
  FROM cohort
)
-- Final aggregation by quintile
SELECT
  risk_quintile,
  COUNT(*) AS n,
  ROUND(AVG(died_within_30d) * 100, 2) AS mortality_30d_pct,
  ROUND(AVG(had_complication) * 100, 2) AS major_complication_pct,
  ROUND(APPROX_QUANTILES(CASE WHEN died_within_30d = 0 THEN los_days END, 2)[OFFSET(1)], 2) AS median_survivor_los_days
FROM quintiles
GROUP BY risk_quintile
ORDER BY risk_quintile;