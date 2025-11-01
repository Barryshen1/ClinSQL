WITH ugid_patients AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(DAY FROM (a.dischtime - a.admittime)) AS los_days
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
    INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a 
      ON p.subject_id = a.subject_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d 
      ON a.hadm_id = d.hadm_id
    INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd 
      ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND d.seq_num = 1
    AND (
      LOWER(dicd.long_title) LIKE '%gastrointestinal hemorrhage%'
      OR LOWER(dicd.long_title) LIKE '%upper gastrointestinal hemorrhage%'
      OR LOWER(dicd.long_title) LIKE '%hemorrhage of upper gastrointestinal tract%'
      OR LOWER(dicd.long_title) LIKE '%upper gi bleed%'
      OR LOWER(dicd.long_title) LIKE '%upper gi hemorrhage%'
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
iqr_calc AS (
  SELECT 
    PERCENTILE_CONT(los_days, 0.25) OVER () AS q1,
    PERCENTILE_CONT(los_days, 0.75) OVER () AS q3
  FROM ugid_patients
)
SELECT 
  q3 - q1 AS iqr_los_days
FROM iqr_calc
LIMIT 1;