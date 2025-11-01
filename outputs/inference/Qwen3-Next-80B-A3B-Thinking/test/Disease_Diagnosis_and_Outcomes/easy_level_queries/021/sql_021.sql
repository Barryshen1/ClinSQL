WITH diagnoses AS (
  SELECT 
    di.hadm_id,
    MAX(CASE WHEN d.long_title LIKE '%hemorrhagic stroke%' 
              OR d.long_title LIKE '%intracerebral hemorrhage%' 
              OR d.long_title LIKE '%subarachnoid hemorrhage%' 
             THEN 1 ELSE 0 END) AS has_hemorrhagic_stroke,
    MAX(CASE WHEN d.long_title LIKE '%COPD exacerbation%' 
              OR d.long_title LIKE '%acute exacerbation of COPD%' 
             THEN 1 ELSE 0 END) AS has_copd_exacerbation
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  GROUP BY di.hadm_id
),
los_data AS (
  SELECT 
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN diagnoses d 
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 58 AND 68
    AND d.has_hemorrhagic_stroke = 1
    AND d.has_copd_exacerbation = 1
)
SELECT 
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY los) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY los) AS iqr
FROM los_data;