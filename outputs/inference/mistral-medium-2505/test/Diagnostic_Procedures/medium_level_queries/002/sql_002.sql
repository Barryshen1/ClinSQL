WITH
-- Get male patients aged 64-74
male_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 64 AND 74
),

-- Get TIA diagnoses (ICD-10 G45.* or ICD-9 435.*)
tia_diagnoses AS (
  SELECT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code LIKE 'G45.%' OR icd_code LIKE '435.%'
),

-- Get admissions with LOS 1-7 days
valid_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
         WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
         ELSE NULL END AS los_category,
    CASE WHEN EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
    ) THEN 'Yes' ELSE 'No' END AS icu_use
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN male_patients mp ON a.subject_id = mp.subject_id
  JOIN tia_diagnoses td ON a.subject_id = td.subject_id AND a.hadm_id = td.hadm_id
  WHERE TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Get ultrasound and echocardiogram procedures
procedures AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    h.hcpcs_cd,
    d.long_description
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d ON h.hcpcs_cd = d.code
  WHERE h.hcpcs_cd IN (
    -- Ultrasound codes
    '76700', '76705', '76770', '76775', '76801', '76802', '76810', '76811', '76815',
    '76816', '76817', '76825', '76826', '76827', '76828', '76856', '76857', '76870',
    '76871', '76872', '76881', '76882', '76930', '76937', '76942', '76945', '76946',
    '76970', '76975', '76977', '76981', '76982', '76985', '76990', '76998', '76999',
    -- Echocardiogram codes
    '93303', '93304', '93306', '93307', '93308', '93312', '93313', '93314', '93315',
    '93316', '93317', '93318', '93320', '93321', '93325', '93350', '93351', '93352'
  )
)

-- Final aggregation
SELECT
  va.los_category,
  va.icu_use,
  COUNT(DISTINCT p.hadm_id) AS admission_count,
  COUNT(p.hadm_id) AS total_procedures,
  COUNT(p.hadm_id) / COUNT(DISTINCT p.hadm_id) AS mean_procedures_per_admission
FROM valid_admissions va
LEFT JOIN procedures p ON va.subject_id = p.subject_id AND va.hadm_id = p.hadm_id
GROUP BY va.los_category, va.icu_use
ORDER BY va.los_category, va.icu_use;