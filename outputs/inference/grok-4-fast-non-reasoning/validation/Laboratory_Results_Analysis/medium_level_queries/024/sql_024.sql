WITH chest_pain_adms AS (
  -- Identify admissions with primary chest pain diagnosis (ICD-10 R07.*)
  SELECT DISTINCT 
    ad.subject_id,
    ad.hadm_id,
    ad.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ad.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON ad.hadm_id = CAST(diag.hadm_id AS INT64)
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND diag.seq_num = 1
    AND diag.icd_version = '10'
    AND diag.icd_code LIKE 'R07.%'
),
first_troponin AS (
  -- Get first hs-Troponin T per qualifying admission
  SELECT 
    cpa.subject_id,
    cpa.hadm_id,
    cpa.hospital_expire_flag,
    le.valuenum,
    ROW_NUMBER() OVER (
      PARTITION BY cpa.hadm_id 
      ORDER BY le.charttime ASC
    ) AS rn
  FROM chest_pain_adms cpa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON cpa.subject_id = le.subject_id
    AND cpa.hadm_id = CAST(le.hadm_id AS INT64)
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE dli.label LIKE '%TroponinT%'
    AND dli.category = 'Chemistry'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 14  -- Exceeds 99th percentile (ng/L)
)
SELECT 
  COUNT(*) AS total_qualifying_admissions,
  ROUND(AVG(valuenum), 2) AS avg_first_hs_troponin_t,
  ROUND(STDDEV(valuenum), 2) AS stddev_first_hs_troponin_t,
  MIN(valuenum) AS min_first_hs_troponin_t,
  MAX(valuenum) AS max_first_hs_troponin_t,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS in_hospital_mortality_rate_percent
FROM first_troponin
WHERE rn = 1;