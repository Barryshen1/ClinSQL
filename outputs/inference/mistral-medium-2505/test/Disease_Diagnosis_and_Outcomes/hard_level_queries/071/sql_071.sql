WITH
-- Define age range and gender
patient_cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),

-- Identify AMI patients
ami_patients AS (
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM
    patient_cohort p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id AND p.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I21.%' OR d.icd_code LIKE 'I22.%'
),

-- Identify ICU stays
icu_stays AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los AS icu_los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    ami_patients a
    ON i.subject_id = a.subject_id AND i.hadm_id = a.hadm_id
),

-- Calculate SAPS-II score components
saps_components AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.charttime,
    c.itemid,
    c.valuenum,
    d.label,
    d.category
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  JOIN
    icu_stays i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  WHERE
    c.charttime BETWEEN i.intime AND i.intime + INTERVAL 24 HOUR
    AND d.category IN ('Vital Signs', 'Labs', 'Other')
),

-- Calculate SAPS-II score (simplified version)
saps_scores AS (
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    -- Simplified SAPS-II calculation (actual calculation would be more complex)
    SUM(
      CASE
        WHEN label = 'Heart Rate' AND valuenum > 120 THEN 5
        WHEN label = 'Systolic Blood Pressure' AND valuenum < 100 THEN 10
        WHEN label = 'Temperature' AND valuenum > 39 THEN 5
        WHEN label = 'Glasgow Coma Score' AND valuenum < 13 THEN 10
        ELSE 0
      END
    ) AS saps_score
  FROM
    saps_components
  GROUP BY
    subject_id, hadm_id, stay_id
),

-- Calculate 90-day mortality
mortality AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.admittime,
    p.deathtime,
    p.hospital_expire_flag,
    CASE
      WHEN p.deathtime IS NOT NULL AND p.deathtime <= p.admittime + INTERVAL 90 DAY THEN 1
      ELSE 0
    END AS died_within_90_days
  FROM
    patient_cohort p
  JOIN
    ami_patients a
    ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
),

-- Age-matched general inpatients (no AMI, no ICU)
general_inpatients AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.admittime,
    p.dischtime,
    p.deathtime,
    p.hospital_expire_flag,
    EXTRACT(DAY FROM p.dischtime - p.admittime) AS los
  FROM
    patient_cohort p
  WHERE
    p.subject_id NOT IN (SELECT subject_id FROM ami_patients)
    AND p.hadm_id NOT IN (SELECT hadm_id FROM icu_stays)
),

-- Major complications (simplified definition)
complications AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN d.icd_code IN (
        'I95.9', 'J96.0', 'E87.2', 'R57.9', 'I46.9', 'G93.6', 'N17.9', 'K72.9'
      ) THEN 1
      ELSE 0
    END AS has_major_complication
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    patient_cohort p
    ON d.subject_id = p.subject_id AND d.hadm_id = p.hadm_id
),

-- Combine AMI with ICU data
ami_icu_data AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    s.saps_score,
    m.died_within_90_days,
    c.has_major_complication,
    EXTRACT(DAY FROM p.dischtime - p.admittime) AS los
  FROM
    mortality m
  JOIN
    patient_cohort p ON m.subject_id = p.subject_id AND m.hadm_id = p.hadm_id
  JOIN
    complications c ON m.subject_id = c.subject_id AND m.hadm_id = c.hadm_id
  JOIN
    saps_scores s ON m.subject_id = s.subject_id AND m.hadm_id = s.hadm_id
),

-- General inpatient data with complications
general_inpatient_data AS (
  SELECT
    g.subject_id,
    g.hadm_id,
    c.has_major_complication,
    g.los
  FROM
    general_inpatients g
  JOIN
    complications c ON g.subject_id = c.subject_id AND g.hadm_id = c.hadm_id
),

-- Calculate risk percentiles
risk_percentiles AS (
  SELECT
    PERCENTILE_CONT(saps_score, 0.5) OVER() AS median_risk_score,
    PERCENTILE_CONT(saps_score, 0.9) OVER() AS p90_risk_score
  FROM
    saps_scores
  LIMIT 1
)

-- Final analysis
SELECT
  'AMI with ICU' AS cohort,
  COUNT(DISTINCT a.subject_id) AS patient_count,
  PERCENTILE_CONT(a.saps_score, 0.5) OVER() AS median_saps_score,
  PERCENTILE_CONT(a.saps_score, 0.25) OVER() AS saps_iqr_lower,
  PERCENTILE_CONT(a.saps_score, 0.75) OVER() AS saps_iqr_upper,
  AVG(a.died_within_90_days) * 100 AS mortality_rate_90d,
  AVG(a.has_major_complication) * 100 AS complication_rate,
  AVG(CASE WHEN a.died_within_90_days = 0 THEN a.los ELSE NULL END) AS avg_los_survivors,
  r.median_risk_score,
  r.p90_risk_score
FROM
  ami_icu_data a
CROSS JOIN
  risk_percentiles r

UNION ALL

SELECT
  'Age-matched General' AS cohort,
  COUNT(DISTINCT g.subject_id) AS patient_count,
  NULL AS median_saps_score,
  NULL AS saps_iqr_lower,
  NULL AS saps_iqr_upper,
  NULL AS mortality_rate_90d,
  AVG(g.has_major_complication) * 100 AS complication_rate,
  AVG(g.los) AS avg_los_survivors,
  NULL AS median_risk_score,
  NULL AS p90_risk_score
FROM
  general_inpatient_data g;