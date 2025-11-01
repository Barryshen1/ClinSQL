WITH first_troponin_t AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.labevents le
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_labitems dli
    ON le.itemid = dli.itemid
  WHERE 
    dli.label = 'Troponin T'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND le.valuenum > 0.04
),
cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  INNER JOIN 
    first_troponin_t ft
    ON a.hadm_id = ft.hadm_id AND ft.rn = 1
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 58 AND 68
    AND (
      LOWER(did.long_title) LIKE '%acute myocardial infarction%'
      OR LOWER(did.long_title) LIKE '%chest pain%'
    )
)
SELECT 
  COUNT(*) AS total_admissions,
  SUM(hospital_expire_flag) AS deaths,
  AVG(hospital_expire_flag) * 100 AS in_hospital_mortality_rate_percent
FROM 
  cohort;