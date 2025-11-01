WITH akp_patients AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS hospital_los
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
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND d.seq_num = 1
    AND LOWER(dicd.long_title) LIKE '%acute kidney injury%'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
iqr_calc AS (
  SELECT 
    PERCENTILE_CONT(hospital_los, 0.25) OVER() AS q1,
    PERCENTILE_CONT(hospital_los, 0.75) OVER() AS q3
  FROM 
    akp_patients
  LIMIT 1
)
SELECT 
  q3 - q1 AS iqr_hospital_los
FROM 
  iqr_calc;