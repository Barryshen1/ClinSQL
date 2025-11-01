WITH
-- Step 1: Identify heart failure admissions (ICD-9: 428.*, ICD-10: I50.*)
heart_failure_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^428'))
      OR (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^I50'))
    )
),

-- Step 1b: Controls (same age/gender, no heart failure)
control_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND a.hadm_id NOT IN (
      SELECT hadm_id FROM heart_failure_admissions
    )
),

-- Step 2: Lab instability score for heart failure admissions (first 48h)
hf_lab_instability AS (
  SELECT
    hfa.hadm_id,
    COUNTIF(l.flag IS NOT NULL AND LOWER(l.flag) != 'normal') AS instability_score,
    COUNTIF(LOWER(l.flag) = 'critical') AS critical_lab_count,
    COUNT(*) AS total_lab_count
  FROM
    heart_failure_admissions hfa
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON hfa.hadm_id = l.hadm_id
      AND l.charttime >= hfa.admittime
      AND l.charttime < DATETIME_ADD(hfa.admittime, INTERVAL 48 HOUR)
  GROUP BY hfa.hadm_id
),

-- Step 2b: Lab instability score for controls (first 48h)
control_lab_instability AS (
  SELECT
    ca.hadm_id,
    COUNTIF(LOWER(l.flag) = 'critical') AS critical_lab_count,
    COUNT(*) AS total_lab_count
  FROM
    control_admissions ca
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON ca.hadm_id = l.hadm_id
      AND l.charttime >= ca.admittime
      AND l.charttime < DATETIME_ADD(ca.admittime, INTERVAL 48 HOUR)
  GROUP BY ca.hadm_id
),

-- Step 3: 95th percentile threshold for instability score
hf_instability_percentile AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[95] AS instability_95th
  FROM hf_lab_instability
),

-- Step 4: Select heart failure admissions above threshold
hf_above_threshold AS (
  SELECT
    hfa.hadm_id,
    hfa.instability_score,
    hfa.critical_lab_count,
    hfa.total_lab_count
  FROM
    hf_lab_instability hfa
    CROSS JOIN hf_instability_percentile p
  WHERE
    hfa.instability_score >= p.instability_95th
),

-- Step 5: Outcomes for above-threshold heart failure admissions
hf_outcomes AS (
  SELECT
    COUNT(*) AS n_above_threshold,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_rate,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND)/86400.0) AS mean_los_days,
    SUM(hf.critical_lab_count) / NULLIF(SUM(hf.total_lab_count), 0) AS critical_lab_rate
  FROM
    hf_above_threshold hf
    JOIN heart_failure_admissions a
      ON hf.hadm_id = a.hadm_id
),

-- Step 6: Outcomes for controls
control_outcomes AS (
  SELECT
    SUM(cl.critical_lab_count) / NULLIF(SUM(cl.total_lab_count), 0) AS control_critical_lab_rate
  FROM
    control_lab_instability cl
)

-- Final output
SELECT
  p.instability_95th AS instability_95th_percentile,
  o.n_above_threshold AS n_above_threshold_patients,
  o.in_hospital_mortality_rate,
  o.mean_los_days,
  o.critical_lab_rate AS hf_critical_lab_rate,
  c.control_critical_lab_rate
FROM
  hf_instability_percentile p,
  hf_outcomes o,
  control_outcomes c;