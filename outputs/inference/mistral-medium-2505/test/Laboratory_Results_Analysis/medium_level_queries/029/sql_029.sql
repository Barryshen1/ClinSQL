WITH
-- Get male patients aged 58-68
male_patients AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 58 AND 68
),

-- Get admissions with chest pain or AMI diagnoses
relevant_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
  WHERE
    -- Chest pain (ICD-9: 786.50, ICD-10: R07.9) or AMI (ICD-9: 410.x, ICD-10: I21.x)
    (d.icd_code LIKE '786.5%' OR d.icd_code LIKE '410.%' OR d.icd_code LIKE 'R07.9%' OR d.icd_code LIKE 'I21.%')
),

-- Get first Troponin T > 0.04 ng/mL per admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE
    l.itemid = 50930  -- Troponin T
    AND l.valuenum > 0.04
    AND l.valueuom = 'ng/mL'
),

-- Combine all criteria
cohort AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    ra.hadm_id,
    ra.admittime,
    ra.dischtime,
    ra.hospital_expire_flag,
    ft.valuenum AS troponin_value,
    ft.valueuom AS troponin_unit,
    ft.charttime AS troponin_time
  FROM
    male_patients p
  JOIN
    relevant_admissions ra
  ON
    p.subject_id = ra.subject_id
  JOIN
    first_troponin ft
  ON
    ra.subject_id = ft.subject_id
    AND ra.hadm_id = ft.hadm_id
  WHERE
    ft.rn = 1  -- First Troponin T measurement
    -- Ensure Troponin T is measured within 24 hours of admission
    AND TIMESTAMP_DIFF(ft.charttime, ra.admittime, HOUR) <= 24
)

-- Final summary statistics
SELECT
  COUNT(DISTINCT subject_id) AS total_patients,
  COUNT(DISTINCT hadm_id) AS total_admissions,
  AVG(anchor_age) AS avg_age,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS in_hospital_deaths,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(DISTINCT hadm_id), 2) AS mortality_rate_percent,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)) AS avg_length_of_stay_hours
FROM
  cohort;