WITH
-- Get female patients aged 52-62
female_patients AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 52 AND 62
),

-- Get AMI admissions (ICD-10 codes I21.x)
ami_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I21.%'
    AND d.icd_version = 10
),

-- Get first Troponin T >0.01 ng/mL per admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di
  ON
    l.itemid = di.itemid
  WHERE
    l.itemid = 3051  -- Troponin T
    AND l.valuenum > 0.01
    AND di.label = 'Troponin T'
),

-- Combine all data
combined_data AS (
  SELECT
    fp.subject_id,
    aa.hadm_id,
    fp.anchor_age,
    aa.los_days,
    aa.hospital_expire_flag,
    ft.troponin_value
  FROM
    female_patients fp
  JOIN
    ami_admissions aa
  ON
    fp.subject_id = aa.subject_id
  JOIN
    first_troponin ft
  ON
    fp.subject_id = ft.subject_id AND aa.hadm_id = ft.hadm_id
  WHERE
    ft.rn = 1  -- Only first Troponin T measurement
)

-- Final aggregation
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(DISTINCT hadm_id) AS admission_count,
  ROUND(AVG(anchor_age), 1) AS mean_age,
  ROUND(AVG(los_days), 1) AS mean_los_days,
  MIN(troponin_value) AS min_first_troponin,
  MAX(troponin_value) AS max_first_troponin,
  ROUND(AVG(troponin_value), 3) AS mean_first_troponin,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality_count,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS in_hospital_mortality_rate
FROM
  combined_data;