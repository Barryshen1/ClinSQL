WITH
-- Define chest pain ICD codes (ICD-10 and ICD-9)
chest_pain_icd AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('R07.1', 'R07.2', 'R07.4', '786.50', '786.51', '786.52', '786.59')
),

-- Get admissions with chest pain diagnosis
admissions_with_chest_pain AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN chest_pain_icd c ON d.icd_code = c.icd_code AND d.icd_version = c.icd_version
),

-- Get male patients aged 64-74
eligible_patients AS (
  SELECT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 64 AND 74
),

-- Get first hs-Troponin T measurement per admission (assuming itemid 50912 for hs-Troponin T)
first_hs_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE d.label = 'hs-Troponin T' AND l.valuenum IS NOT NULL
),

-- Filter for first hs-Troponin T > 14 ng/L (99th percentile)
high_troponin_patients AS (
  SELECT f.subject_id, f.hadm_id, f.charttime, f.valuenum
  FROM first_hs_troponin f
  WHERE f.rn = 1 AND f.valuenum > 14
)

-- Final cohort: eligible patients with chest pain and high troponin
SELECT
  COUNT(DISTINCT h.subject_id) AS patient_count,
  COUNT(DISTINCT h.hadm_id) AS admission_count,
  AVG(h.valuenum) AS avg_hs_troponin,
  MIN(h.valuenum) AS min_hs_troponin,
  MAX(h.valuenum) AS max_hs_troponin,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_deaths,
  ROUND(
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 /
    COUNT(DISTINCT h.subject_id),
    2
  ) AS in_hospital_mortality_rate_percentage
FROM high_troponin_patients h
JOIN admissions_with_chest_pain a ON h.subject_id = a.subject_id AND h.hadm_id = a.hadm_id
JOIN eligible_patients e ON h.subject_id = e.subject_id;