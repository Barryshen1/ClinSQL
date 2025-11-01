WITH patients_cohort AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'M'
    AND anchor_age BETWEEN 59 AND 69
),
acs_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (
    (icd_version = 9 AND icd_code IN ('410', '411.1'))
    OR (icd_version = 10 AND (SUBSTR(icd_code, 1, 3) IN ('I21', 'I22') OR icd_code = 'I20.0'))
  )
),
admissions_with_los AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_cohort p ON a.subject_id = p.subject_id
  WHERE a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.dischtime > a.admittime
),
acs_admissions AS (
  SELECT
    di.hadm_id,
    CASE WHEN di.seq_num = 1 THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN acs_codes ac ON di.icd_code = ac.icd_code AND di.icd_version = ac.icd_version
  GROUP BY di.hadm_id, diagnosis_type
),
admissions_stratified AS (
  SELECT
    a.hadm_id,
    a.los_days,
    ac.diagnosis_type,
    CASE
      WHEN a.los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN a.los_days BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS duration_group
  FROM admissions_with_los a
  INNER JOIN acs_admissions ac ON a.hadm_id = ac.hadm_id
  WHERE a.los_days BETWEEN 1 AND 7
),
procedure_counts AS (
  SELECT
    a.hadm_id,
    a.duration_group,
    a.diagnosis_type,
    COUNT(p.icd_code) AS proc_count
  FROM admissions_stratified a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd p ON a.hadm_id = p.hadm_id
  GROUP BY a.hadm_id, a.duration_group, a.diagnosis_type
)
SELECT
  duration_group,
  diagnosis_type,
  APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] AS p25_procedures,
  APPROX_QUANTILES(proc_count, 100)[OFFSET(50)] AS p50_procedures,
  APPROX_QUANTILES(proc_count, 100)[OFFSET(75)] AS p75_procedures
FROM procedure_counts
GROUP BY duration_group, diagnosis_type
ORDER BY duration_group, diagnosis_type;