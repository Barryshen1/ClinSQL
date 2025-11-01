WITH
  -- Step 1: Define cohort (male, age 42-52, DVT diagnosis) using EXISTS to avoid duplicates
  cohort AS (
    SELECT
      p.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
    FROM
      `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` a
      ON p.subject_id = a.subject_id
    WHERE
      p.gender = 'M'
      AND EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
        WHERE
          di.hadm_id = a.hadm_id
          AND (di.icd_code LIKE '453%' OR di.icd_code LIKE 'I82%')  -- DVT codes
      )
  ),
  filtered_cohort AS (
    SELECT *
    FROM cohort
    WHERE age_admit BETWEEN 42 AND 52
  ),
  -- Step 2: Lab instability score (abnormal labs in first 72 hours)
  lab_score AS (
    SELECT
      c.hadm_id,
      COUNT(l.labevent_id) AS lab_instability_score
    FROM
      filtered_cohort c
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON c.hadm_id = l.hadm_id
      AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
      AND l.flag IS NOT NULL  -- Abnormal labs only
    GROUP BY c.hadm_id
  ),
  -- Step 3: 95th percentile of the score
  percentile AS (
    SELECT
      APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(95)] AS p95
    FROM lab_score
  ),
  -- Step 4: High-score group (≥95th percentile)
  high_score_group AS (
    SELECT
      ls.hadm_id,
      ls.lab_instability_score
    FROM
      lab_score ls
    CROSS JOIN percentile p
    WHERE ls.lab_instability_score >= p.p95
  ),
  -- Step 5a: Critical labs for entire stay (high-score group)
  high_score_critical AS (
    SELECT
      h.hadm_id,
      c.hospital_expire_flag,
      DATE_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
      COUNT(l.labevent_id) AS total_critical_labs
    FROM
      high_score_group h
    JOIN
      filtered_cohort c
      ON h.hadm_id = c.hadm_id
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON h.hadm_id = l.hadm_id
      AND l.charttime BETWEEN c.admittime AND c.dischtime
      AND l.flag IS NOT NULL
    GROUP BY h.hadm_id, c.hospital_expire_flag, los_days
  ),
  -- Step 5b: Critical labs for all inpatients
  all_inpatients_critical AS (
    SELECT
      a.hadm_id,
      COUNT(l.labevent_id) AS total_critical_labs
    FROM
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.hadm_id = l.hadm_id
      AND l.charttime BETWEEN a.admittime AND a.dischtime
      AND l.flag IS NOT NULL
    GROUP BY a.hadm_id
  )
-- Step 6: Final output (high-score group vs. all inpatients)
SELECT
  'High-Score Group' AS cohort_group,
  COUNT(hadm_id) AS num_patients,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_percent,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(total_critical_labs), 2) AS mean_critical_labs
FROM high_score_critical
UNION ALL
SELECT
  'All Inpatients' AS cohort_group,
  COUNT(hadm_id) AS num_patients,
  NULL AS mortality_rate_percent,  -- Not required for all inpatients
  NULL AS mean_los_days,           -- Not required for all inpatients
  ROUND(AVG(total_critical_labs), 2) AS mean_critical_labs
FROM all_inpatients_critical;