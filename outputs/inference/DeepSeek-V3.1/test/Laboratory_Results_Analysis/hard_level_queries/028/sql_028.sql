WITH
-- ICH cohort: women aged 74-84 with ICH
ich_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    pat.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 74 AND 84
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'I61%' AND icd_version = 10
      UNION ALL
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code = '431' AND icd_version = 9
    )
),

-- Control cohort: women aged 74-84 without ICH
control_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 74 AND 84
    AND adm.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code LIKE 'I61%' AND icd_version = 10
      UNION ALL
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE icd_code = '431' AND icd_version = 9
    )
),

-- Labs for ICH cohort within first 72 hours
ich_labs AS (
  SELECT
    lab.subject_id,
    lab.hadm_id,
    lab.itemid,
    lab.flag,
    lab.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  INNER JOIN ich_cohort coh
    ON lab.hadm_id = coh.hadm_id
    AND lab.subject_id = coh.subject_id
  WHERE lab.charttime BETWEEN coh.admittime AND DATETIME_ADD(coh.admittime, INTERVAL 72 HOUR)
),

-- Labs for control cohort within first 72 hours
control_labs AS (
  SELECT
    lab.subject_id,
    lab.hadm_id,
    lab.itemid,
    lab.flag,
    lab.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` lab
  INNER JOIN control_cohort coh
    ON lab.hadm_id = coh.hadm_id
    AND lab.subject_id = coh.subject_id
  WHERE lab.charttime BETWEEN coh.admittime AND DATETIME_ADD(coh.admittime, INTERVAL 72 HOUR)
),

-- For ICH admission, count distinct abnormal labs
ich_abnormal_lab_count AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT itemid) AS num_abnormal_labs
  FROM ich_labs
  WHERE flag = 'abnormal'
  GROUP BY hadm_id
),

-- For ICH admissions without any abnormal labs, we need to include them with 0
ich_admissions_with_ab_count AS (
  SELECT
    coh.hadm_id,
    COALESCE(cnt.num_abnormal_labs, 0) AS num_abnormal_labs,
    coh.hospital_expire_flag,
    coh.los_days
  FROM ich_cohort coh
  LEFT JOIN ich_abnormal_lab_count cnt
    ON coh.hadm_id = cnt.hadm_id
),

-- Assign quintiles based on num_abnormal_labs
ich_with_quintiles AS (
  SELECT
    hadm_id,
    num_abnormal_labs,
    hospital_expire_flag,
    los_days,
    NTILE(5) OVER (ORDER BY num_abnormal_labs) AS quintile
  FROM ich_admissions_with_ab_count
),

-- Mortality and LOS by quintile
quintile_outcomes AS (
  SELECT
    quintile,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(los_days) AS mean_los
  FROM ich_with_quintiles
  GROUP BY quintile
  ORDER BY quintile
),

-- For each lab test, compute abnormality rate in ICH cohort
ich_lab_rates AS (
  SELECT
    itemid,
    COUNT(*) AS total_tests,
    SUM(CASE WHEN flag = 'abnormal' THEN 1 ELSE 0 END) AS abnormal_tests,
    SAFE_DIVIDE(SUM(CASE WHEN flag = 'abnormal' THEN 1 ELSE 0 END), COUNT(*)) AS abnormal_rate
  FROM ich_labs
  GROUP BY itemid
),

-- For each lab test, compute abnormality rate in control cohort
control_lab_rates AS (
  SELECT
    itemid,
    COUNT(*) AS total_tests,
    SUM(CASE WHEN flag = 'abnormal' THEN 1 ELSE 0 END) AS abnormal_tests,
    SAFE_DIVIDE(SUM(CASE WHEN flag = 'abnormal' THEN 1 ELSE 0 END), COUNT(*)) AS abnormal_rate
  FROM control_labs
  GROUP BY itemid
)

-- First, output the quintile outcomes with placeholder columns
SELECT 
  'QUINTILE_OUTCOMES' AS analysis_type,
  CAST(quintile AS STRING) AS quintile,
  NULL AS itemid,
  NULL AS lab_name,
  mortality_rate AS ich_abnormal_rate,
  NULL AS control_abnormal_rate,
  NULL AS rate_difference
FROM quintile_outcomes

UNION ALL

-- Then, output the lab rates comparison for each lab that appears in both cohorts
SELECT
  'LAB_RATES_COMPARISON' AS analysis_type,
  NULL AS quintile,
  CAST(ich.itemid AS STRING) AS itemid,
  dlab.label AS lab_name,
  ich.abnormal_rate AS ich_abnormal_rate,
  ctrl.abnormal_rate AS control_abnormal_rate,
  ich.abnormal_rate - ctrl.abnormal_rate AS rate_difference
FROM ich_lab_rates ich
INNER JOIN control_lab_rates ctrl
  ON ich.itemid = ctrl.itemid
INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
  ON ich.itemid = dlab.itemid;