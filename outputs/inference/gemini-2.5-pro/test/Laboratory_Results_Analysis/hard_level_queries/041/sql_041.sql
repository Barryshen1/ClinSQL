WITH
-- Step 1: Define the base population of male inpatients aged 54-64
male_admissions_in_age_range AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 54 AND 64
),

-- Step 2: Identify admissions with a heart failure diagnosis (Case Group)
hf_admissions AS (
  SELECT DISTINCT
    base.hadm_id,
    base.subject_id,
    base.admittime,
    base.dischtime,
    base.hospital_expire_flag
  FROM
    male_admissions_in_age_range AS base
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
    ON base.hadm_id = dx.hadm_id
  WHERE
    -- ICD-10 codes for Heart Failure start with I50
    -- ICD-9 codes for Heart Failure start with 428
    dx.icd_code LIKE 'I50%' OR dx.icd_code LIKE '428%'
),

-- Step 3: Identify age-matched male admissions without heart failure (Control Group)
control_admissions AS (
  SELECT
    base.hadm_id,
    base.subject_id,
    base.admittime
  FROM
    male_admissions_in_age_range AS base
  WHERE
    base.hadm_id NOT IN (SELECT hadm_id FROM hf_admissions)
),

-- Step 4: Calculate the laboratory instability score for each HF patient (count of abnormal labs in first 48h)
hf_instability_scores AS (
  SELECT
    hf.hadm_id,
    hf.subject_id,
    hf.admittime,
    hf.dischtime,
    hf.hospital_expire_flag,
    COUNT(le.labevent_id) AS laboratory_instability_score
  FROM
    hf_admissions AS hf
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON hf.hadm_id = le.hadm_id
    AND le.charttime BETWEEN hf.admittime AND DATETIME_ADD(hf.admittime, INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY
    hf.hadm_id,
    hf.subject_id,
    hf.admittime,
    hf.dischtime,
    hf.hospital_expire_flag
),

-- Step 5: Determine the 95th percentile instability score to define the high-risk threshold
instability_threshold AS (
  SELECT
    APPROX_QUANTILES(laboratory_instability_score, 100)[OFFSET(95)] AS p95_score
  FROM
    hf_instability_scores
),

-- Step 6: Calculate outcomes for the high-risk HF subgroup (those at or above the 95th percentile score)
high_risk_outcomes AS (
  SELECT
    COUNT(DISTINCT hfs.hadm_id) AS num_patients_high_risk,
    SUM(hfs.laboratory_instability_score) AS total_abnormal_labs_high_risk,
    AVG(CAST(hfs.hospital_expire_flag AS FLOAT64)) AS mortality_rate_high_risk,
    AVG(DATETIME_DIFF(hfs.dischtime, hfs.admittime, HOUR) / 24.0) AS mean_los_days_high_risk
  FROM
    hf_instability_scores AS hfs
  CROSS JOIN
    instability_threshold AS it
  WHERE
    hfs.laboratory_instability_score >= it.p95_score
),

-- Step 7: Calculate the rate of critical labs for the control group
control_lab_rate AS (
  SELECT
    COUNT(le.labevent_id) AS total_abnormal_labs,
    (SELECT COUNT(DISTINCT hadm_id) FROM control_admissions) AS num_patients_control
  FROM
    control_admissions AS ca
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON ca.hadm_id = le.hadm_id
    AND le.charttime BETWEEN ca.admittime AND DATETIME_ADD(ca.admittime, INTERVAL 48 HOUR)
    AND le.flag = 'abnormal'
)

-- Step 8: Assemble the final report
SELECT
  it.p95_score AS percentile_95_instability_score,
  hro.mortality_rate_high_risk,
  hro.mean_los_days_high_risk,
  -- Critical-lab rate is abnormal labs per patient per day. Window is 2 days.
  SAFE_DIVIDE(hro.total_abnormal_labs_high_risk, hro.num_patients_high_risk * 2.0) AS critical_lab_rate_high_risk,
  SAFE_DIVIDE(clr.total_abnormal_labs, clr.num_patients_control * 2.0) AS critical_lab_rate_control
FROM
  instability_threshold AS it,
  high_risk_outcomes AS hro,
  control_lab_rate AS clr;