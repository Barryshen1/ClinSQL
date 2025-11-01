WITH sepsis_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10 
    AND (long_title LIKE '%sepsis%' OR long_title LIKE '%Sepsis%')
),
male_sepsis_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    DATE(a.dischtime) AS discharge_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN sepsis_codes sc 
    ON d.icd_code = sc.icd_code
  WHERE p.gender = 'M'
  GROUP BY p.subject_id, a.hadm_id, discharge_date
),
lactate_measurements AS (
  SELECT 
    m.subject_id,
    m.hadm_id,
    m.discharge_date,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY m.subject_id, m.hadm_id ORDER BY l.charttime DESC) AS rn
  FROM male_sepsis_patients m
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON m.subject_id = l.subject_id 
    AND m.hadm_id = l.hadm_id
    AND DATE(l.charttime) = m.discharge_date
    AND l.itemid = 50809  -- serum lactate
    AND l.valuenum IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr
FROM lactate_measurements
WHERE rn = 1;