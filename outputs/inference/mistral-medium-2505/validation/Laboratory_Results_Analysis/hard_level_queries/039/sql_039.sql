WITH
-- Define the cohort: male inpatients aged 60-70 with primary pneumonia
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.dod,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND d.seq_num = 1  -- Primary diagnosis
    AND d.icd_code IN ('J18.9', 'J15.9')  -- Pneumonia ICD codes
),

-- Calculate the 72-hour Laboratory Instability Score (LIS)
lis_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    -- Calculate LIS components (example: WBC, creatinine, bilirubin, etc.)
    -- This is a simplified example; actual LIS calculation may vary
    MAX(CASE WHEN l.itemid = 51301 THEN l.valuenum ELSE NULL END) AS wbc,
    MAX(CASE WHEN l.itemid = 50912 THEN l.valuenum ELSE NULL END) AS creatinine,
    MAX(CASE WHEN l.itemid = 50885 THEN l.valuenum ELSE NULL END) AS bilirubin,
    -- Add other lab components as needed
    -- Calculate LIS score (example formula)
    (CASE
      WHEN MAX(CASE WHEN l.itemid = 51301 THEN l.valuenum ELSE NULL END) > 12 THEN 1 ELSE 0 END +
     CASE
      WHEN MAX(CASE WHEN l.itemid = 50912 THEN l.valuenum ELSE NULL END) > 2 THEN 1 ELSE 0 END +
     CASE
      WHEN MAX(CASE WHEN l.itemid = 50885 THEN l.valuenum ELSE NULL END) > 2 THEN 1 ELSE 0 END) AS lis_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.labevents` l ON c.hadm_id = l.hadm_id
  WHERE
    l.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id
),

-- Calculate critical-event frequency for the cohort
cohort_critical_events AS (
  SELECT
    c.hadm_id,
    COUNT(DISTINCT ce.subject_id) AS critical_event_count
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON c.hadm_id = ce.hadm_id
  WHERE
    -- Example: critical events like abnormal vitals or procedures
    ce.itemid IN (220045, 220046, 220047)  -- Example itemids for critical events
    AND ce.charttime BETWEEN c.admittime AND c.dischtime
  GROUP BY
    c.hadm_id
),

-- Calculate critical-event frequency for all inpatients
all_inpatients_critical_events AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT ce.subject_id) AS critical_event_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce ON a.hadm_id = ce.hadm_id
  WHERE
    ce.itemid IN (220045, 220046, 220047)  -- Example itemids for critical events
    AND ce.charttime BETWEEN a.admittime AND a.dischtime
  GROUP BY
    a.hadm_id
),

-- Calculate LOS and mortality for the cohort
cohort_los_mortality AS (
  SELECT
    c.hadm_id,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24 AS los_days,
    c.hospital_expire_flag AS mortality
  FROM
    cohort c
)

-- Final results
SELECT
  -- 75th percentile of LIS score
  APPROX_QUANTILES(lis_score, 100)[OFFSET(75)] AS lis_75th_percentile,
  -- Mean critical-event frequency comparison
  AVG(cc.critical_event_count) AS cohort_mean_critical_events,
  AVG(a.critical_event_count) AS all_inpatients_mean_critical_events,
  -- Cohort LOS and mortality
  AVG(cl.los_days) AS cohort_avg_los_days,
  SUM(CASE WHEN cl.mortality = 1 THEN 1 ELSE 0 END) / COUNT(*) AS cohort_mortality_rate
FROM
  lis_scores l
JOIN
  cohort_critical_events cc ON l.hadm_id = cc.hadm_id
JOIN
  all_inpatients_critical_events a ON l.hadm_id = a.hadm_id
JOIN
  cohort_los_mortality cl ON l.hadm_id = cl.hadm_id;