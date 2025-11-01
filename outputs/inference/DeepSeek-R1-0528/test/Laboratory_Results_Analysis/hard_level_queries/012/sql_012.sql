WITH base_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
),
ami_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '410%') OR
    (icd_version = 10 AND (icd_code LIKE 'I21%' OR icd_code LIKE 'I22%'))
),
cohort_with_ami AS (
  SELECT 
    bc.*,
    CASE WHEN ami.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_ami
  FROM base_cohort bc
  LEFT JOIN ami_admissions ami
    ON bc.hadm_id = ami.hadm_id
  WHERE bc.age_at_admission BETWEEN 44 AND 54
),
critical_labs AS (
  SELECT 
    c.hadm_id,
    c.is_ami,
    COUNT(labe.labevent_id) AS critical_lab_count
  FROM cohort_with_ami c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` labe
    ON c.hadm_id = labe.hadm_id
    AND c.subject_id = labe.subject_id
    AND labe.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND labe.flag IS NOT NULL  -- Critical labs only
  GROUP BY c.hadm_id, c.is_ami
),
ami_critical_labs AS (
  SELECT critical_lab_count
  FROM critical_labs
  WHERE is_ami = 1
),
percentile_75 AS (
  SELECT 
    APPROX_QUANTILES(critical_lab_count, 100)[OFFSET(75)] AS p75_lab_instability
  FROM ami_critical_labs
),
avg_critical_comparison AS (
  SELECT 
    is_ami,
    AVG(critical_lab_count) AS avg_critical_lab_count
  FROM critical_labs
  GROUP BY is_ami
),
ami_cohort_outcomes AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days,
    hospital_expire_flag
  FROM cohort_with_ami
  WHERE is_ami = 1
),
los_stats AS (
  SELECT 
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS los_25p,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_median,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_75p
  FROM ami_cohort_outcomes
),
mortality_stats AS (
  SELECT 
    COUNT(*) AS total_count,
    SUM(hospital_expire_flag) AS death_count,
    ROUND(SUM(hospital_expire_flag) * 100.0 / COUNT(*), 2) AS mortality_percentage
  FROM ami_cohort_outcomes
)
SELECT
  (SELECT p75_lab_instability FROM percentile_75) AS p75_lab_instability,
  (SELECT avg_critical_lab_count FROM avg_critical_comparison WHERE is_ami = 1) AS ami_avg_critical_lab,
  (SELECT avg_critical_lab_count FROM avg_critical_comparison WHERE is_ami = 0) AS control_avg_critical_lab,
  (SELECT los_median FROM los_stats) AS los_median,
  (SELECT los_25p FROM los_stats) AS los_25p,
  (SELECT los_75p FROM los_stats) AS los_75p,
  (SELECT death_count FROM mortality_stats) AS death_count,
  (SELECT total_count FROM mortality_stats) AS total_count,
  (SELECT mortality_percentage FROM mortality_stats) AS mortality_percentage;