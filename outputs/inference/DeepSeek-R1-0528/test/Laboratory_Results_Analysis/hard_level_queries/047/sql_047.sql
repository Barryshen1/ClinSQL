WITH
target_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND adm.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (icd_code = '51882' AND icd_version = 9)
        OR (icd_code = 'J80' AND icd_version = 10)
    )
),
first_icu AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime
  FROM target_cohort t
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON t.hadm_id = i.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) = 1
),
target_labs AS (
  SELECT
    f.stay_id,
    f.subject_id,
    f.hadm_id,
    COUNT(le.labevent_id) AS abnormal_count
  FROM first_icu f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON f.hadm_id = le.hadm_id
    AND le.charttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY f.stay_id, f.subject_id, f.hadm_id
),
percentile AS (
  SELECT
    APPROX_QUANTILES(abnormal_count, 100) AS p
  FROM target_labs
),
threshold AS (
  SELECT p[OFFSET(90)] AS threshold_value
  FROM percentile
),
target_above AS (
  SELECT
    tl.*
  FROM target_labs tl
  CROSS JOIN threshold t
  WHERE tl.abnormal_count >= t.threshold_value
),
target_outcomes AS (
  SELECT
    ta.stay_id,
    ta.subject_id,
    ta.hadm_id,
    ta.abnormal_count,
    adm.hospital_expire_flag,
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_hospital
  FROM target_above ta
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ta.hadm_id = adm.hadm_id
),
control_cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND adm.hadm_id NOT IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (icd_code = '51882' AND icd_version = 9)
        OR (icd_code = 'J80' AND icd_version = 10)
    )
),
control_icu AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    i.stay_id,
    i.intime
  FROM control_cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.hadm_id = i.hadm_id
  QUALIFY ROW_NUMBER() OVER (PARTITION BY i.hadm_id ORDER BY i.intime) = 1
),
control_labs AS (
  SELECT
    f.stay_id,
    f.subject_id,
    f.hadm_id,
    COUNT(le.labevent_id) AS abnormal_count
  FROM control_icu f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON f.hadm_id = le.hadm_id
    AND le.charttime BETWEEN f.intime AND DATETIME_ADD(f.intime, INTERVAL 72 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY f.stay_id, f.subject_id, f.hadm_id
)
SELECT
  'Target (≥90th Percentile)' AS cohort,
  COUNT(*) AS num_patients,
  AVG(hospital_expire_flag) * 100 AS mortality_rate_percent,
  AVG(los_hospital) AS mean_los_days,
  AVG(abnormal_count) AS mean_abnormal_labs
FROM target_outcomes
UNION ALL
SELECT
  'Control (General Inpatients)' AS cohort,
  COUNT(*) AS num_patients,
  NULL AS mortality_rate_percent,
  NULL AS mean_los_days,
  AVG(abnormal_count) AS mean_abnormal_labs
FROM control_labs;