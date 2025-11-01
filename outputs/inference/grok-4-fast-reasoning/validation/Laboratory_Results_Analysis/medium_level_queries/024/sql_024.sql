WITH troponin_labs AS (
  SELECT 
    le.hadm_id, 
    le.charttime, 
    le.valuenum, 
    le.ref_range_upper,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li 
    ON le.itemid = li.itemid
  WHERE LOWER(li.label) LIKE '%troponin t%' 
    AND li.category = 'Chemistry'
    AND le.valuenum IS NOT NULL 
    AND le.ref_range_upper IS NOT NULL
),
first_troponin AS (
  SELECT 
    hadm_id, 
    valuenum AS first_val, 
    ref_range_upper AS first_upper
  FROM troponin_labs
  WHERE rn = 1
),
qualifying_hadm AS (
  SELECT hadm_id
  FROM first_troponin
  WHERE first_val > first_upper
),
chest_pain_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%chest pain%'
)
SELECT 
  COUNT(*) AS num_admissions,
  COUNT(DISTINCT p.subject_id) AS num_patients,
  AVG(p.anchor_age) AS avg_age,
  MIN(p.anchor_age) AS min_age,
  MAX(p.anchor_age) AS max_age,
  SUM(a.hospital_expire_flag) AS num_deaths,
  SAFE_DIVIDE(SUM(a.hospital_expire_flag), COUNT(*)) AS mortality_rate
FROM `physionet-data.mimiciv_3_1_hosp.patients` p
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
  ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
  ON a.hadm_id = diag.hadm_id AND diag.seq_num = 1
JOIN chest_pain_codes cpc 
  ON diag.icd_code = cpc.icd_code AND diag.icd_version = cpc.icd_version
JOIN qualifying_hadm q 
  ON a.hadm_id = q.hadm_id
WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 64 AND 74;