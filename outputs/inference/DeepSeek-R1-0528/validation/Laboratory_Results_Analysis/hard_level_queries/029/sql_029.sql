WITH
base_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
),
age_filtered_patients AS (
  SELECT
    *,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admit
  FROM base_patients
  WHERE anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 50 AND 60
),
hhs_patients AS (
  SELECT DISTINCT
    afp.*
  FROM age_filtered_patients afp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON afp.subject_id = diag.subject_id
    AND afp.hadm_id = diag.hadm_id
  WHERE
    (diag.icd_version = 9 AND diag.icd_code LIKE '2502%')
    OR (diag.icd_version = 10 AND diag.icd_code IN ('E1100', 'E1101'))
),
non_hhs_patients AS (
  SELECT
    afp.*
  FROM age_filtered_patients afp
  WHERE NOT EXISTS (
    SELECT 1
    FROM hhs_patients hp
    WHERE afp.subject_id = hp.subject_id
      AND afp.hadm_id = hp.hadm_id
  )
),
hhs_labs AS (
  SELECT
    hp.subject_id,
    hp.hadm_id,
    MAX(CASE WHEN le.itemid = 50983 THEN le.valuenum END) AS max_sodium,
    MAX(CASE WHEN le.itemid = 50931 THEN le.valuenum END) AS max_glucose,
    MAX(CASE WHEN le.itemid = 51006 THEN le.valuenum END) AS max_bun
  FROM hhs_patients hp
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hp.subject_id = le.subject_id
    AND hp.hadm_id = le.hadm_id
    AND le.charttime BETWEEN hp.admittime AND DATETIME_ADD(hp.admittime, INTERVAL 48 HOUR)
    AND le.itemid IN (50983, 50931, 51006)
  GROUP BY hp.subject_id, hp.hadm_id
  HAVING
    MAX(CASE WHEN le.itemid = 50983 THEN le.valuenum END) IS NOT NULL
    AND MAX(CASE WHEN le.itemid = 50931 THEN le.valuenum END) IS NOT NULL
    AND MAX(CASE WHEN le.itemid = 51006 THEN le.valuenum END) IS NOT NULL
),
hhs_scores AS (
  SELECT
    hl.*,
    hp.admittime,
    hp.dischtime,
    hp.hospital_expire_flag,
    2 * max_sodium + (max_glucose / 18) + (max_bun / 2.8) AS instability_score
  FROM hhs_labs hl
  INNER JOIN hhs_patients hp
    ON hl.subject_id = hp.subject_id
    AND hl.hadm_id = hp.hadm_id
),
percentile AS (
  SELECT
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75_score
  FROM hhs_scores
),
high_risk_hhs AS (
  SELECT
    hs.*
  FROM hhs_scores hs
  CROSS JOIN percentile p
  WHERE hs.instability_score >= p.p75_score
),
high_risk_critical_labs AS (
  SELECT
    hrh.subject_id,
    hrh.hadm_id,
    COUNT(le.labevent_id) AS critical_lab_count
  FROM high_risk_hhs hrh
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON hrh.subject_id = le.subject_id
    AND hrh.hadm_id = le.hadm_id
    AND le.charttime BETWEEN hrh.admittime AND DATETIME_ADD(hrh.admittime, INTERVAL 48 HOUR)
    AND le.flag = 'panic'
  GROUP BY hrh.subject_id, hrh.hadm_id
),
control_critical_labs AS (
  SELECT
    nhp.subject_id,
    nhp.hadm_id,
    COUNT(le.labevent_id) AS critical_lab_count
  FROM non_hhs_patients nhp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON nhp.subject_id = le.subject_id
    AND nhp.hadm_id = le.hadm_id
    AND le.charttime BETWEEN nhp.admittime AND DATETIME_ADD(nhp.admittime, INTERVAL 48 HOUR)
    AND le.flag = 'panic'
  GROUP BY nhp.subject_id, nhp.hadm_id
),
high_risk_summary AS (
  SELECT
    COUNT(*) AS n_high_risk,
    SUM(hrh.hospital_expire_flag) AS n_deaths,
    AVG(DATETIME_DIFF(hrh.dischtime, hrh.admittime, DAY)) AS mean_los_days,
    AVG(COALESCE(hrcl.critical_lab_count, 0)) AS avg_critical_labs
  FROM high_risk_hhs hrh
  LEFT JOIN high_risk_critical_labs hrcl
    ON hrh.subject_id = hrcl.subject_id
    AND hrh.hadm_id = hrcl.hadm_id
),
control_summary AS (
  SELECT
    AVG(COALESCE(ccl.critical_lab_count, 0)) AS avg_critical_labs_control
  FROM control_critical_labs ccl
)
SELECT
  n_high_risk,
  n_deaths,
  n_deaths / n_high_risk AS mortality_rate,
  mean_los_days,
  avg_critical_labs,
  avg_critical_labs_control
FROM high_risk_summary, control_summary;