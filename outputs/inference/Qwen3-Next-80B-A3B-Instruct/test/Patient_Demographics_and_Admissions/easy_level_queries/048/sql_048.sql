WITH first_admissions AS (
  SELECT 
    p.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON d.icd_code = did.icd_code 
    AND d.icd_version = did.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND LOWER(did.long_title) LIKE '%heart failure%'
),
ranked_first_admissions AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM 
    first_admissions
)
SELECT 
  PERCENTILE_CONT(los_days, 0.75) - PERCENTILE_CONT(los_days, 0.25) AS iqr_los_days
FROM 
  ranked_first_admissions
WHERE 
  rn = 1;