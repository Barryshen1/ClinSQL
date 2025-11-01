WITH ami_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id AND adm.subject_id = diag.subject_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 90 AND 100
    AND (
      (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%') 
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
    )
),

labs AS (
  SELECT 
    lab.hadm_id,
    lab.itemid,
    lab.valuenum,
    lab.ref_range_lower,
    lab.ref_range_upper,
    lab.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  INNER JOIN ami_cohort coh
    ON lab.hadm_id = coh.hadm_id AND lab.subject_id = coh.subject_id
  WHERE 
    lab.charttime BETWEEN coh.admittime AND DATETIME_ADD(coh.admittime, INTERVAL 48 HOUR)
    AND lab.valuenum IS NOT NULL
    AND lab.ref_range_lower IS NOT NULL
    AND lab.ref_range_upper IS NOT NULL
),

abnormal_labs AS (
  SELECT 
    hadm_id,
    itemid,
    COUNTIF(valuenum < ref_range_lower OR valuenum > ref_range_upper) AS is_abnormal
  FROM labs
  GROUP BY hadm_id, itemid
),

lab_instability AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_abnormal_labs
  FROM abnormal_labs
  WHERE is_abnormal = 1
  GROUP BY hadm_id
),

percentile_calc AS (
  SELECT 
    APPROX_QUANTILES(num_abnormal_labs, 100)[OFFSET(75)] AS p75
  FROM lab_instability
),

high_risk_cohort AS (
  SELECT 
    coh.*,
    li.num_abnormal_labs
  FROM ami_cohort coh
  LEFT JOIN lab_instability li
    ON coh.hadm_id = li.hadm_id
  WHERE li.num_abnormal_labs >= (SELECT p75 FROM percentile_calc)
),

all_90_100 AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.anchor_age BETWEEN 90 AND 100
),

results_high_risk AS (
  SELECT 
    'High Risk (>=P75 Lab Instability)' AS cohort,
    COUNT(*) AS n_patients,
    AVG(1.0 * hospital_expire_flag) AS in_hospital_mortality,
    AVG(los_days) AS mean_los_days,
    NULL AS critical_lab_rate  -- Placeholder, will compute separately
  FROM high_risk_cohort
),

critical_lab_rate_high_risk AS (
  SELECT 
    COUNTIF(valuenum < ref_range_lower OR valuenum > ref_range_upper) * 1.0 / COUNT(*) AS crit_rate
  FROM labs
  INNER JOIN high_risk_cohort coh
    ON labs.hadm_id = coh.hadm_id
),

results_all_90_100 AS (
  SELECT 
    'All Inpatients 90-100' AS cohort,
    COUNT(*) AS n_patients,
    AVG(1.0 * hospital_expire_flag) AS in_hospital_mortality,
    AVG(los_days) AS mean_los_days,
    NULL AS critical_lab_rate  -- Placeholder
  FROM all_90_100
),

critical_lab_rate_all AS (
  SELECT 
    COUNTIF(valuenum < ref_range_lower OR valuenum > ref_range_upper) * 1.0 / COUNT(*) AS crit_rate
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  INNER JOIN all_90_100 coh
    ON lab.hadm_id = coh.hadm_id AND lab.subject_id = coh.subject_id
  WHERE 
    lab.charttime BETWEEN coh.admittime AND DATETIME_ADD(coh.admittime, INTERVAL 48 HOUR)
    AND lab.valuenum IS NOT NULL
    AND lab.ref_range_lower IS NOT NULL
    AND lab.ref_range_upper IS NOT NULL
)

SELECT 
  r.cohort,
  r.n_patients,
  r.in_hospital_mortality,
  r.mean_los_days,
  CASE 
    WHEN r.cohort = 'High Risk (>=P75 Lab Instability)' THEN (SELECT crit_rate FROM critical_lab_rate_high_risk)
    WHEN r.cohort = 'All Inpatients 90-100' THEN (SELECT crit_rate FROM critical_lab_rate_all)
  END AS critical_lab_rate
FROM (
  SELECT * FROM results_high_risk
  UNION ALL
  SELECT * FROM results_all_90_100
) r;