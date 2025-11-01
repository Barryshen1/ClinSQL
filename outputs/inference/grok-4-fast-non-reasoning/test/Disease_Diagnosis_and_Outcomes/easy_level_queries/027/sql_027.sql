WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 49 AND 59
),
upper_gi_bleed_adms AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd
    ON d.icd_code = icd.icd_code 
    AND d.icd_version = icd.icd_version
  WHERE 
    d.seq_num = 1
    AND d.icd_version = 10
    AND (
      LOWER(icd.long_title) LIKE '%upper gastrointestinal bleed%'
      OR LOWER(icd.long_title) LIKE '%upper gi bleed%'
      OR d.icd_code LIKE 'K25.%'  -- Gastric ulcer with hemorrhage
      OR d.icd_code IN ('K22.0', 'K22.1', 'K92.0', 'K92.2')  -- Varices, hematemesis, GI hemorrhage
    )
)
SELECT 
  MAX(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS max_los_days
FROM 
  `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN 
  eligible_patients ep
  ON a.subject_id = ep.subject_id
INNER JOIN 
  upper_gi_bleed_adms ugb
  ON a.subject_id = ugb.subject_id 
  AND a.hadm_id = ugb.hadm_id
WHERE 
  a.hospital_expire_flag = 0
  AND a.dischtime > a.admittime;