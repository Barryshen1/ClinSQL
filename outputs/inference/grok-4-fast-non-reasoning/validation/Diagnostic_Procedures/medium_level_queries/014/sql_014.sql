WITH acs_admissions AS (
  -- Filter male patients aged 83-93 with ACS diagnoses
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    d.seq_num,
    CASE WHEN d.seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_type
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
    AND d.icd_code LIKE 'I2%'  -- ACS: I20-I22 (unstable angina, acute/subsequent MI)
    AND a.hospital_expire_flag = 0  -- Exclude in-hospital deaths (LOS=0)
),
los_stratified AS (
  -- Add LOS stratum
  SELECT 
    *,
    DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS los_days,
    CASE 
      WHEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) BETWEEN 5 AND 7 THEN '5-7 days'
      ELSE 'Other'
    END AS los_stratum
  FROM acs_admissions
  WHERE DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) BETWEEN 1 AND 7  -- Focus on specified strata
),
ultrasounds AS (
  -- Identify ultrasound procedures per admission
  SELECT 
    pe.hadm_id,
    COUNT(DISTINCT CASE WHEN di.category = 'Imaging' OR di.label LIKE '%echo%' OR di.label LIKE '%ultrasound%' THEN pe.itemid END) AS ultrasound_count
  FROM 
    `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON pe.itemid = di.itemid
  GROUP BY pe.hadm_id
),
admissions_with_ultrasounds AS (
  -- Join ultrasounds to admissions (default to 0 if no procedures)
  SELECT 
    ls.*,
    COALESCE(u.ultrasound_count, 0) AS ultrasound_count
  FROM los_stratified ls
  LEFT JOIN ultrasounds u
  ON ls.hadm_id = u.hadm_id
  WHERE los_stratum != 'Other'  -- Only 1-4 and 5-7 days
)
-- Aggregate statistics by strata
SELECT 
  'Male 83-93' AS demographic_group,
  los_stratum,
  diagnosis_type,
  COUNT(*) AS num_admissions,
  AVG(ultrasound_count) AS mean_ultrasounds,
  MIN(ultrasound_count) AS min_ultrasounds,
  MAX(ultrasound_count) AS max_ultrasounds
FROM admissions_with_ultrasounds
GROUP BY los_stratum, diagnosis_type
ORDER BY los_stratum, diagnosis_type;