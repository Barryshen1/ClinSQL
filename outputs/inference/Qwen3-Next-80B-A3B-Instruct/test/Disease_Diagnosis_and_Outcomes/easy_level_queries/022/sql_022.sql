WITH stroke_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code 
    AND d.icd_version = dicd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
    AND d.seq_num = 1
    AND LOWER(dicd.long_title) LIKE '%ischemic stroke%'
    OR LOWER(dicd.long_title) LIKE '%cerebral infarction%'
),
iqr_calc AS (
  SELECT 
    PERCENTILE_CONT(los_days, 0.25) OVER () AS q1,
    PERCENTILE_CONT(los_days, 0.75) OVER () AS q3
  FROM 
    stroke_patients
)
SELECT 
  q3 - q1 AS iqr_los_days
FROM 
  iqr_calc
LIMIT 1;