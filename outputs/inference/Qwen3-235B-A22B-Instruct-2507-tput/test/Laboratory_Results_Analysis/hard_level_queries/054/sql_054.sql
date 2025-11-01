WITH admission_age AS (
  SELECT
    p.subject_id,
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admittime AS admission_start,
    DATETIME_ADD(a.admittime, INTERVAL 72 HOUR) AS admission_72h
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_year IS NOT NULL
    AND a.admittime IS NOT NULL
),

ami_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE icd_version = 10
    AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%' OR icd_code LIKE 'I23%')
),

ami_cohort AS (
  SELECT DISTINCT aa.*
  FROM admission_age aa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON aa.hadm_id = di.hadm_id
  INNER JOIN ami_codes ac
    ON di.icd_code = ac.icd_code
  WHERE aa.age_at_admission BETWEEN 38 AND 48
),

non_ami_controls AS (
  SELECT aa.*
  FROM admission_age aa
  WHERE aa.age_at_admission BETWEEN 38 AND 48
    AND aa.hadm_id NOT IN (SELECT hadm_id FROM ami_cohort)
),

lab_abnormalities AS (
  SELECT
    le.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM `physionet-data.mimiciv_3_1_hosp`.labevents le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.charttime >= (SELECT MIN(admission_start) FROM admission_age) -- performance; actual filter below
    AND (le.valuenum < ref_range_lower OR le.valuenum > ref_range_upper)
  GROUP BY le.hadm_id
),

ami_with_labs AS (
  SELECT
    ac.*,
    COALESCE(lab.abnormal_lab_count, 0) AS lab_instability_score
  FROM ami_cohort ac
  LEFT JOIN lab_abnormalities lab
    ON ac.hadm_id = lab.hadm_id
),

controls_with_labs AS (
  SELECT
    c.*,
    COALESCE(lab.abnormal_lab_count, 0) AS lab_instability_score
  FROM non_ami_controls c
  LEFT JOIN lab_abnormalities lab
    ON c.hadm_id = lab.hadm_id
),

ami_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY lab_instability_score) AS quartile
  FROM ami_with_labs
)

-- Final result: two parts
-- Part 1: Quartile analysis for AMI patients
SELECT
  CAST(quartile AS STRING) AS group_label,
  COUNT(*) AS patient_count,
  ROUND(AVG(IF(dischtime IS NOT NULL, DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0, NULL)), 2) AS median_los_days,
  ROUND(AVG(hospital_expire_flag), 3) AS mortality_rate
FROM ami_quartiles
GROUP BY quartile

UNION ALL

-- Part 2: Critical lab rate comparison (AMI vs Controls)
SELECT
  'AMI' AS group_label,
  COUNT(*) AS patient_count,
  ROUND(AVG(lab_instability_score), 2) AS median_los_days, -- repurposed: avg lab instability
  ROUND(AVG(CASE WHEN lab_instability_score > 0 THEN 1.0 ELSE 0.0 END), 3) AS mortality_rate -- critical lab rate
FROM ami_with_labs

UNION ALL

SELECT
  'Control' AS group_label,
  COUNT(*) AS patient_count,
  ROUND(AVG(lab_instability_score), 2) AS median_los_days,
  ROUND(AVG(CASE WHEN lab_instability_score > 0 THEN 1.0 ELSE 0.0 END), 3) AS mortality_rate
FROM controls_with_labs

ORDER BY group_label;