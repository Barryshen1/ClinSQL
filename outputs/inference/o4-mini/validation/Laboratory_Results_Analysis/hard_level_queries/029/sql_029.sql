WITH
-- 1. Identify female, age 50-60 admissions with HHS
hhs_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      USING(subject_id, hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND LOWER(dd.long_title) LIKE '%hyperosmolar%'
),

-- 2. Compute instability scores for each HHS admission
hhs_instability AS (
  SELECT
    h.hadm_id,
    COUNT(DISTINCT l.itemid) AS instability_score,
    COUNT(DISTINCT l.itemid) AS total_tests_48h,
    COUNTIF(l.flag IS NOT NULL) AS abnormal_tests_48h
  FROM
    hhs_cohort h
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON h.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN h.admittime AND TIMESTAMP_ADD(h.admittime, INTERVAL 48 HOUR)
  GROUP BY
    h.hadm_id
),

-- 3. Compute the 75th percentile instability threshold
threshold AS (
  SELECT
    APPROX_QUANTILES(instability_score, 4)[OFFSET(3)] AS instab_75
  FROM
    hhs_instability
),

-- 4A. Metrics for HHS admissions with high instability
hhs_high AS (
  SELECT
    hi.hadm_id,
    hi.instability_score,
    h.hospital_expire_flag,
    TIMESTAMP_DIFF(h.dischtime, h.admittime, DAY) AS los_days,
    SAFE_DIVIDE(hi.abnormal_tests_48h, hi.total_tests_48h) AS critical_lab_rate
  FROM
    hhs_instability hi
    CROSS JOIN threshold t
    JOIN hhs_cohort h
      ON hi.hadm_id = h.hadm_id
  WHERE
    hi.instability_score >= t.instab_75
),

-- 4B. Metrics for general female 50–60 inpatients (no HHS)
general_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
      USING(subject_id)
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.hadm_id NOT IN (SELECT hadm_id FROM hhs_cohort)
),

general_instability AS (
  SELECT
    g.hadm_id,
    COUNT(DISTINCT l.itemid) AS total_tests_48h,
    COUNTIF(l.flag IS NOT NULL) AS abnormal_tests_48h
  FROM
    general_cohort g
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON g.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN g.admittime AND TIMESTAMP_ADD(g.admittime, INTERVAL 48 HOUR)
  GROUP BY
    g.hadm_id
),

general_metrics AS (
  SELECT
    SAFE_DIVIDE(SUM(abnormal_tests_48h), SUM(total_tests_48h)) AS general_critical_lab_rate
  FROM
    general_instability
)

-- 5. Final output: threshold, HHS-high metrics, and comparison rate
SELECT
  ANY_VALUE(t.instab_75) AS instability_75th_percentile,
  ROUND(AVG(CAST(hh.hospital_expire_flag AS FLOAT64)), 3) AS mortality_rate,
  ROUND(AVG(hh.los_days), 2) AS mean_los_days,
  ROUND(AVG(hh.critical_lab_rate), 3) AS hhs_high_critical_lab_rate,
  ANY_VALUE(ROUND(gm.general_critical_lab_rate, 3)) AS general_critical_lab_rate
FROM
  hhs_high hh
  CROSS JOIN threshold t
  CROSS JOIN general_metrics gm;