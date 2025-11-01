WITH ultrasound_proc_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%ultrasound%' OR LOWER(long_title) LIKE '%echocardiography%'
),
admissions_filtered AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admission_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 73 AND 83
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime >= a.admittime
),
ultrasound_counts AS (
  SELECT
    af.hadm_id,
    af.los_days,
    CASE
      WHEN af.admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED'
      WHEN af.admission_type = 'ELECTIVE' THEN 'ELECTIVE'
      ELSE 'OTHER'
    END AS adm_type,
    COUNT(*) AS ultrasound_count
  FROM admissions_filtered af
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON af.hadm_id = proc.hadm_id
  JOIN ultrasound_proc_codes upc
    ON proc.icd_code = upc.icd_code
    AND proc.icd_version = upc.icd_version
  WHERE af.los_days BETWEEN 1 AND 7
  GROUP BY af.hadm_id, af.los_days, adm_type
),
stratified_data AS (
  SELECT
    ultrasound_count,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    END AS los_group,
    adm_type
  FROM ultrasound_counts
  WHERE adm_type IN ('ED', 'ELECTIVE')
)
SELECT
  los_group,
  adm_type,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM stratified_data
GROUP BY los_group, adm_type
ORDER BY los_group, adm_type;