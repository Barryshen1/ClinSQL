WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 50 AND 60
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 8
),
has_acs AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    icd_version = 9 
    AND (icd_code LIKE '410%' OR icd_code = '411.1')
  ) OR (
    icd_version = 10 
    AND (icd_code = 'I20.0' OR icd_code LIKE 'I21%')
  )
),
primary_acs AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num = 1
    AND (
      (icd_version = 9 
      AND (icd_code LIKE '410%' OR icd_code = '411.1'))
      OR
      (icd_version = 10 
      AND (icd_code = 'I20.0' OR icd_code LIKE 'I21%'))
    )
),
filtered_cohort AS (
  SELECT 
    c.hadm_id,
    c.los,
    CASE WHEN pa.hadm_id IS NOT NULL THEN 'primary' ELSE 'secondary' END AS diagnosis_type
  FROM cohort c
  INNER JOIN has_acs h
    ON c.hadm_id = h.hadm_id
  LEFT JOIN primary_acs pa
    ON c.hadm_id = pa.hadm_id
),
proc_counts AS (
  SELECT 
    fc.hadm_id,
    fc.los,
    fc.diagnosis_type,
    COUNT(pi.icd_code) AS num_diagnostic_procedures
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON fc.hadm_id = pi.hadm_id
  GROUP BY fc.hadm_id, fc.los, fc.diagnosis_type
)
SELECT 
  CASE WHEN los <= 4 THEN '1-4' ELSE '5-8' END AS los_group,
  diagnosis_type,
  APPROX_QUANTILES(num_diagnostic_procedures, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(num_diagnostic_procedures, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(num_diagnostic_procedures, 4)[OFFSET(3)] AS p75
FROM proc_counts
GROUP BY los_group, diagnosis_type
ORDER BY los_group, diagnosis_type;