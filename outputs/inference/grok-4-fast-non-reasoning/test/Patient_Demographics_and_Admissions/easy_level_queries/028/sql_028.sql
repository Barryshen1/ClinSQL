WITH sepsis_patients AS (
  SELECT DISTINCT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    CAST(d.hadm_id AS STRING) AS hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
    AND d.icd_version = '10'
    AND d.icd_code LIKE 'A41%'
)
SELECT 
  STDDEV_POP(los / 24.0) AS stddev_icu_los_days
FROM 
  sepsis_patients sp
INNER JOIN 
  `physionet-data.mimiciv_3_1_icu.icustays` i
  ON sp.subject_id = i.subject_id
  AND sp.hadm_id = i.hadm_id;