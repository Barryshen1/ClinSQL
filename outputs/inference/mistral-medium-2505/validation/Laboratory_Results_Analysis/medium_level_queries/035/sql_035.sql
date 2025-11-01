WITH
-- Get male patients aged 73-83
male_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 73 AND 83
),

-- Get admissions with ACS (using ICD-9/10 codes for ACS)
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    -- ICD-9 codes for ACS (e.g., 410.xx)
    (d.icd_code LIKE '410.%' AND d.icd_version = 9)
    -- ICD-10 codes for ACS (e.g., I21.x)
    OR (d.icd_code LIKE 'I21.%' AND d.icd_version = 10)
),

-- Get first Troponin T lab test per admission
first_troponin AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` di
    ON l.itemid = di.itemid
  WHERE
    -- Troponin T itemid (example: 30000, but verify in d_labitems)
    di.label LIKE '%Troponin T%'
    AND l.valuenum > 0.1  -- Elevated threshold (adjust as needed)
),

-- Filter for admissions with elevated initial Troponin T
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS length_of_stay
  FROM
    acs_admissions a
  JOIN
    first_troponin ft
    ON a.subject_id = ft.subject_id AND a.hadm_id = ft.hadm_id
  WHERE
    ft.rn = 1  -- First Troponin T test
)

-- Calculate cohort statistics
SELECT
  COUNT(*) AS cohort_size,
  AVG(length_of_stay) AS avg_length_of_stay,
  SUM(hospital_expire_flag) AS in_hospital_deaths,
  SUM(hospital_expire_flag) / COUNT(*) AS in_hospital_mortality_rate
FROM
  cohort;