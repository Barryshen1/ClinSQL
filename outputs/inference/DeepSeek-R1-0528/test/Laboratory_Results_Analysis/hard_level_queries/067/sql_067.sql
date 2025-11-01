WITH base_cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS admission_age,
    CASE WHEN d.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS acs_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE 
      (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code IN ('411.1', '411.81')))
      OR 
      (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code IN ('I20.0', 'I24.8', 'I24.9')))
  ) d 
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 53 AND 63
),
labs AS (
  SELECT 
    le.hadm_id,
    le.itemid,
    le.valuenum,
    le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN base_cohort b
    ON le.hadm_id = b.hadm_id
  WHERE 
    le.charttime BETWEEN b.admittime AND DATETIME_ADD(b.admittime, INTERVAL 72 HOUR)
    AND le.itemid IN (50971, 50983, 50912, 50931, 51222)
    AND le.valuenum IS NOT NULL
),
lab_flags AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN itemid = 50971 AND (valuenum < 3.0 OR valuenum > 6.0) THEN 1 ELSE 0 END) AS potassium_critical,
    MAX(CASE WHEN itemid = 50983 AND (valuenum < 130 OR valuenum > 150) THEN 1 ELSE 0 END) AS sodium_critical,
    MAX(CASE WHEN itemid = 50912 AND valuenum > 1.5 THEN 1 ELSE 0 END) AS creatinine_critical,
    MAX(CASE WHEN itemid = 50931 AND (valuenum < 50 OR valuenum > 400) THEN 1 ELSE 0 END) AS glucose_critical,
    MAX(CASE WHEN itemid = 51222 AND valuenum < 7 THEN 1 ELSE 0 END) AS hemoglobin_critical
  FROM labs
  GROUP BY hadm_id
),
cohort_with_labs AS (
  SELECT 
    b.*,
    COALESCE(l.potassium_critical, 0) AS potassium_critical,
    COALESCE(l.sodium_critical, 0) AS sodium_critical,
    COALESCE(l.creatinine_critical, 0) AS creatinine_critical,
    COALESCE(l.glucose_critical, 0) AS glucose_critical,
    COALESCE(l.hemoglobin_critical, 0) AS hemoglobin_critical
  FROM base_cohort b
  LEFT JOIN lab_flags l
    ON b.hadm_id = l.hadm_id
),
acs_cohort AS (
  SELECT 
    *,
    potassium_critical + sodium_critical + creatinine_critical + 
    glucose_critical + hemoglobin_critical AS instability_score
  FROM cohort_with_labs
  WHERE acs_flag = 1
),
acs_with_quartile AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY instability_score) AS quartile
  FROM acs_cohort
)
-- Part 1: Mortality & LOS per quartile for ACS patients
SELECT 
  'Part1' AS part,
  quartile,
  COUNT(*) AS num_patients,
  AVG(hospital_expire_flag) * 100 AS mortality_percentage,
  AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los_days,
  NULL AS group_name,
  NULL AS potassium_critical_rate,
  NULL AS sodium_critical_rate,
  NULL AS creatinine_critical_rate,
  NULL AS glucose_critical_rate,
  NULL AS hemoglobin_critical_rate
FROM acs_with_quartile
GROUP BY quartile

UNION ALL

-- Part 2: Critical lab rates for ACS vs. controls
SELECT 
  'Part2' AS part,
  NULL AS quartile,
  NULL AS num_patients,
  NULL AS mortality_percentage,
  NULL AS avg_los_days,
  CASE 
    WHEN acs_flag = 1 THEN 'ACS Patients' 
    ELSE 'Control Group' 
  END AS group_name,
  AVG(potassium_critical) * 100 AS potassium_critical_rate,
  AVG(sodium_critical) * 100 AS sodium_critical_rate,
  AVG(creatinine_critical) * 100 AS creatinine_critical_rate,
  AVG(glucose_critical) * 100 AS glucose_critical_rate,
  AVG(hemoglobin_critical) * 100 AS hemoglobin_critical_rate
FROM cohort_with_labs
GROUP BY group_name
ORDER BY part, quartile, group_name;