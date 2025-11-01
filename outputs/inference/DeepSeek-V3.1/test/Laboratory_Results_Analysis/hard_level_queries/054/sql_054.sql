WITH
cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    CASE WHEN di.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ami
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  LEFT JOIN (
    SELECT DISTINCT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE
      (icd_version = 10 AND icd_code LIKE 'I21%')
      OR (icd_version = 9 AND icd_code LIKE '410%')
  ) di ON a.hadm_id = di.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),

selected_labs AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE itemid IN (50971, 50983, 50912, 50931, 51003, 50911)  -- K, Na, Creat, Glucose, Troponin T, Troponin I
),

labs_72h AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.has_ami,
    l.itemid,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper,
    -- Check if abnormal: below lower or above upper
    CASE
      WHEN l.valuenum < l.ref_range_lower OR l.valuenum > l.ref_range_upper THEN 1
      ELSE 0
    END AS is_abnormal
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  INNER JOIN selected_labs sl
    ON l.itemid = sl.itemid
  WHERE l.valuenum IS NOT NULL
    AND l.ref_range_lower IS NOT NULL
    AND l.ref_range_upper IS NOT NULL
),

abnormal_count_per_patient AS (
  SELECT
    subject_id,
    hadm_id,
    has_ami,
    COUNT(DISTINCT itemid) AS total_abnormal_labs  -- Count distinct lab tests that were abnormal
  FROM labs_72h
  WHERE is_abnormal = 1
  GROUP BY subject_id, hadm_id, has_ami
),

ami_patients AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COALESCE(a.total_abnormal_labs, 0) AS lab_instability_score,
    -- Calculate length of stay in days
    DATE_DIFF(DATE(c.dischtime), DATE(c.admittime), DAY) AS los_days
  FROM cohort c
  LEFT JOIN abnormal_count_per_patient a
    ON c.hadm_id = a.hadm_id
  WHERE c.has_ami = 1
),

ami_with_quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY lab_instability_score) AS quartile
  FROM ami_patients
),

-- For AMI quartiles: report quartile ranges, count, avg LOS, mortality rate
ami_quartile_summary AS (
  SELECT
    quartile,
    MIN(lab_instability_score) AS min_score,
    MAX(lab_instability_score) AS max_score,
    COUNT(*) AS num_patients,
    ROUND(AVG(los_days), 2) AS avg_los_days,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_percent
  FROM ami_with_quartiles
  GROUP BY quartile
),

-- Compare overall critical-lab rates between AMI and controls
control_vs_ami AS (
  SELECT
    has_ami,
    COUNT(*) AS num_patients,
    ROUND(AVG(COALESCE(total_abnormal_labs, 0)), 2) AS avg_abnormal_labs
  FROM cohort c
  LEFT JOIN abnormal_count_per_patient a
    ON c.hadm_id = a.hadm_id
  GROUP BY has_ami
)

-- Output both results
SELECT * FROM ami_quartile_summary
ORDER BY quartile;

SELECT * FROM control_vs_ami;