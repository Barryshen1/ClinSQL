WITH 
-- Define sepsis and septic shock
sepsis AS (
  SELECT 
    di.subject_id, 
    di.hadm_id,
    CASE 
      WHEN di.icd_code IN ('99591', '99592', '785.52') THEN 'septic_shock'
      WHEN di.icd_code IN ('038', '481', '482', '483', '484', '485', '486', '487.1') THEN 'sepsis'
      ELSE NULL 
    END AS condition
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
),
charlson AS (
  SELECT 
    dg.subject_id,
    dg.hadm_id,
    CASE 
      WHEN dg.drg_severity <= 3 THEN 'charlson_3_or_less'
      WHEN dg.drg_severity BETWEEN 4 AND 5 THEN 'charlson_4_5'
      ELSE 'charlson_more_than_5'
    END AS charlson_group
  FROM 
    `physionet-data.mimiciv_3_1_hosp.drgcodes` dg
),
patient_info AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN 'los_7_or_less'
      ELSE 'los_more_than_7'
    END AS los_group
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 57 AND 67 AND p.gender = 'F'
),
sepsis_patients AS (
  SELECT 
    sp.subject_id,
    sp.hadm_id,
    sp.condition
  FROM 
    sepsis sp
  WHERE 
    sp.condition IS NOT NULL
),
final_data AS (
  SELECT 
    pi.subject_id,
    pi.hadm_id,
    pi.los_group,
    cz.charlson_group,
    sp.condition,
    pi.hospital_expire_flag
  FROM 
    patient_info pi
  JOIN 
    sepsis_patients sp 
  ON 
    pi.hadm_id = sp.hadm_id
  JOIN 
    charlson cz 
  ON 
    pi.hadm_id = cz.hadm_id
)

-- Calculate mortality by condition, LOS, and Charlson score
SELECT 
  fd.condition,
  fd.los_group,
  fd.charlson_group,
  COUNT(fd.subject_id) AS total_patients,
  SUM(fd.hospital_expire_flag) AS deaths,
  (SUM(fd.hospital_expire_flag) * 1.0 / COUNT(fd.subject_id)) * 100 AS mortality_percentage
FROM 
  final_data fd
GROUP BY 
  fd.condition,
  fd.los_group,
  fd.charlson_group
ORDER BY 
  fd.condition,
  fd.los_group,
  fd.charlson_group;