WITH ami_cohort AS (
  -- Female AMI admissions aged 90-100
  SELECT DISTINCT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    AND (
      (d.icd_version = '9' AND REGEXP_CONTAINS(d.icd_code, r'^410\.'))
      OR
      (d.icd_version = '10' AND REGEXP_CONTAINS(d.icd_code, r'^I21\.'))
    )
    AND a.dischtime > a.admittime
),

lab_flags AS (
  -- Critical lab derangements in first 48h (MAX per type to indicate occurrence)
  SELECT 
    l.hadm_id,
    MAX(CASE WHEN LOWER(li.label) LIKE '%creatinine%' 
             AND l.valueuom IS NOT NULL 
             AND l.valueuom = 'mg/dl' 
             AND COALESCE(l.valuenum, 0) > 2.0 THEN 1 ELSE 0 END) AS flag_creatinine,
    MAX(CASE WHEN LOWER(li.label) LIKE '%potassium%' 
             AND l.valueuom IS NOT NULL 
             AND l.valueuom = 'mEq/L' 
             AND (COALESCE(l.valuenum, 0) < 3.5 OR COALESCE(l.valuenum, 0) > 5.0) THEN 1 ELSE 0 END) AS flag_potassium,
    MAX(CASE WHEN LOWER(li.label) LIKE '%sodium%' 
             AND l.valueuom IS NOT NULL 
             AND l.valueuom = 'mEq/L' 
             AND (COALESCE(l.valuenum, 0) < 135 OR COALESCE(l.valuenum, 0) > 145) THEN 1 ELSE 0 END) AS flag_sodium,
    MAX(CASE WHEN LOWER(li.label) LIKE '%troponin%' 
             AND l.valueuom IS NOT NULL 
             AND l.valueuom = 'ng/mL' 
             AND COALESCE(l.valuenum, 0) > 0.5 THEN 1 ELSE 0 END) AS flag_troponin,
    MAX(CASE WHEN LOWER(li.label) LIKE '%bun%' 
             AND l.valueuom IS NOT NULL 
             AND l.valueuom = 'mg/dl' 
             AND COALESCE(l.valuenum, 0) > 30 THEN 1 ELSE 0 END) AS flag_bun,
    MAX(CASE WHEN LOWER(li.label) LIKE '%hemoglobin%' 
             AND l.valueuom IS NOT NULL 
             AND l.valueuom = 'g/dL' 
             AND COALESCE(l.valuenum, 0) < 10 THEN 1 ELSE 0 END) AS flag_hemoglobin,
    MAX(CASE WHEN LOWER(li.label) LIKE '%wbc%' 
             AND l.valueuom IS NOT NULL 
             AND l.valueuom IN ('x10*3/uL', 'K/uL') 
             AND (COALESCE(l.valuenum, 0) < 4 OR COALESCE(l.valuenum, 0) > 12) THEN 1 ELSE 0 END) AS flag_wbc,
    MAX(CASE WHEN LOWER(li.label) LIKE '%cholesterol, total%' 
             AND l.valueuom IS NOT NULL 
             AND l.valueuom = 'mg/dl' 
             AND COALESCE(l.valuenum, 0) > 200 THEN 1 ELSE 0 END) AS flag_cholesterol
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON l.itemid = li.itemid
  INNER JOIN ami_cohort ac
    ON l.hadm_id = ac.hadm_id
    AND l.charttime >= ac.admittime
    AND l.charttime <= TIMESTAMP_ADD(ac.admittime, INTERVAL 48 HOUR)
  WHERE l.valuenum IS NOT NULL
  GROUP BY l.hadm_id
),

scores AS (
  -- Lab instability score: sum of flags per admission
  SELECT 
    ac.hadm_id,
    ac.admittime,
    ac.dischtime,
    ac.hospital_expire_flag,
    COALESCE(
      lf.flag_creatinine + lf.flag_potassium + lf.flag_sodium + lf.flag_troponin + 
      lf.flag_bun + lf.flag_hemoglobin + lf.flag_wbc + lf.flag_cholesterol, 0
    ) AS lab_score,
    -- Recalculate individual flags for rates (using COALESCE for missing)
    COALESCE(lf.flag_creatinine, 0) AS flag_creatinine,
    COALESCE(lf.flag_potassium, 0) AS flag_potassium,
    COALESCE(lf.flag_troponin, 0) AS flag_troponin,
    COALESCE(lf.flag_sodium, 0) AS flag_sodium
  FROM ami_cohort ac
  LEFT JOIN lab_flags lf
    ON ac.hadm_id = lf.hadm_id
),

p75_calc AS (
  -- Calculate 75th percentile
  SELECT 
    APPROX_QUANTILES(lab_score, 4)[OFFSET(3)] / 4.0 AS p75_value
  FROM scores
),

summary_ami_all AS (
  -- Aggregates for all AMI cohort
  SELECT 
    AVG(hospital_expire_flag) * 100 AS mortality_pct_all,
    AVG(CAST(DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS FLOAT64)) AS mean_los_days_all,
    AVG(COALESCE(flag_creatinine, 0)) * 100 AS crit_creatinine_rate_pct_all,
    AVG(COALESCE(flag_potassium, 0)) * 100 AS crit_potassium_rate_pct_all,
    AVG(COALESCE(flag_troponin, 0)) * 100 AS crit_troponin_rate_pct_all,
    AVG(COALESCE(flag_sodium, 0)) * 100 AS crit_sodium_rate_pct_all
  FROM scores
),

summary_ami_p75 AS (
  -- Aggregates for AMI >=P75
  SELECT 
    AVG(hospital_expire_flag) * 100 AS mortality_pct_p75,
    AVG(CAST(DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS FLOAT64)) AS mean_los_days_p75,
    AVG(COALESCE(flag_creatinine, 0)) * 100 AS crit_creatinine_rate_pct_p75,
    AVG(COALESCE(flag_potassium, 0)) * 100 AS crit_potassium_rate_pct_p75,
    AVG(COALESCE(flag_troponin, 0)) * 100 AS crit_troponin_rate_pct_p75,
    AVG(COALESCE(flag_sodium, 0)) * 100 AS crit_sodium_rate_pct_p75
  FROM scores s
  CROSS JOIN p75_calc p
  WHERE s.lab_score >= p.p75_value
),

all_inpatients AS (
  -- All female inpatients 90-100 (for comparison)
  SELECT 
    AVG(hospital_expire_flag) * 100 AS mortality_pct_all_inpt,
    AVG(CAST(DATE_DIFF(DATE(dischtime), DATE(admittime), DAY) AS FLOAT64)) AS mean_los_days_all_inpt
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    AND a.dischtime > a.admittime
)

-- Final output: P75 score + summaries for >=P75 AMI vs all AMI vs all inpatients
SELECT 
  p.p75_value AS p75_lab_instability_score,
  sa_p75.mortality_pct_p75 AS mortality_pct_ami_p75,
  sa_p75.mean_los_days_p75 AS mean_los_days_ami_p75,
  sa_p75.crit_creatinine_rate_pct_p75 AS crit_creatinine_rate_pct_ami_p75,
  sa_p75.crit_potassium_rate_pct_p75 AS crit_potassium_rate_pct_ami_p75,
  sa_p75.crit_troponin_rate_pct_p75 AS crit_troponin_rate_pct_ami_p75,
  sa_p75.crit_sodium_rate_pct_p75 AS crit_sodium_rate_pct_ami_p75,
  sa_all.mortality_pct_all AS mortality_pct_all_ami,
  sa_all.mean_los_days_all AS mean_los_days_all_ami,
  sa_all.crit_creatinine_rate_pct_all AS crit_creatinine_rate_pct_all_ami,
  sa_all.crit_potassium_rate_pct_all AS crit_potassium_rate_pct_all_ami,
  sa_all.crit_troponin_rate_pct_all AS crit_troponin_rate_pct_all_ami,
  sa_all.crit_sodium_rate_pct_all AS crit_sodium_rate_pct_all_ami,
  ai.mortality_pct_all_inpt AS mortality_pct_all_inpt,
  ai.mean_los_days_all_inpt AS mean_los_days_all_inpt
FROM p75_calc p
CROSS JOIN summary_ami_p75 sa_p75
CROSS JOIN summary_ami_all sa_all
CROSS JOIN all_inpatients ai;