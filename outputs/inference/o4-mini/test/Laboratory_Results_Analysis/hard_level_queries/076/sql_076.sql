WITH
-- Base male 87–97 population
base_adm AS (
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
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
),

-- ACS admissions within that population
acs_adm AS (
  SELECT DISTINCT
    b.subject_id,
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.hospital_expire_flag
  FROM
    base_adm b
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON b.subject_id = d.subject_id
      AND b.hadm_id    = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code    = dd.icd_code
      AND d.icd_version = dd.icd_version
  WHERE
    LOWER(dd.long_title) LIKE '%acute coronary syndrome%'
),

-- Compute 72h instability score per admission (ACS)
acs_instability AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    COUNT(1) AS instability_score
  FROM
    acs_adm a
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON a.subject_id = le.subject_id
      AND a.hadm_id    = le.hadm_id
      AND le.charttime BETWEEN a.admittime
                          AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  WHERE
    le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY
    a.subject_id,
    a.hadm_id
),

-- Calculate 95th percentile for instability_score in ACS cohort
p95 AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[SAFE_OFFSET(95)] AS p95_score
  FROM
    acs_instability
),

-- High‐instability ACS group (>= P95)
high_inst AS (
  SELECT
    ai.subject_id,
    ai.hadm_id,
    ai.instability_score,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    acs_instability ai
    CROSS JOIN p95
    JOIN acs_adm a
      ON ai.subject_id = a.subject_id
      AND ai.hadm_id    = a.hadm_id
  WHERE
    ai.instability_score >= p95.p95_score
),

-- Summary metrics for high‐instability ACS group
high_summary AS (
  SELECT
    COUNT(1) AS n_patients,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, DAY)) AS mean_los_days,
    AVG(hospital_expire_flag) AS in_hosp_mortality_rate,
    AVG(instability_score) AS avg_critical_events_per_patient
  FROM
    high_inst
),

-- General inpatient comparison group: same age/gender but all admissions
gen_instability AS (
  SELECT
    b.subject_id,
    b.hadm_id,
    COUNT(1) AS instability_score
  FROM
    base_adm b
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON b.subject_id = le.subject_id
      AND b.hadm_id    = le.hadm_id
      AND le.charttime BETWEEN b.admittime
                          AND TIMESTAMP_ADD(b.admittime, INTERVAL 72 HOUR)
  WHERE
    le.valuenum IS NOT NULL
    AND le.ref_range_lower IS NOT NULL
    AND le.ref_range_upper IS NOT NULL
    AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
  GROUP BY
    b.subject_id,
    b.hadm_id
),

gen_summary AS (
  SELECT
    AVG(instability_score) AS avg_critical_events_general
  FROM
    gen_instability
)

-- Final output
SELECT
  h.p95_score AS instability_score_95th_percentile,
  hs.mean_los_days,
  hs.in_hosp_mortality_rate,
  hs.avg_critical_events_per_patient,
  gs.avg_critical_events_general
FROM
  p95 h
  CROSS JOIN high_summary hs
  CROSS JOIN gen_summary gs;