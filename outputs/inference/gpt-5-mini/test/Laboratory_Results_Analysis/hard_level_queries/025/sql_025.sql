WITH female_hadm AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
),

hem_diag AS (
  -- hemorrhagic stroke ICD-10 and ICD-9 prefixes
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
     OR (icd_version = 9  AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%'))
),

hadm_cohort AS (
  -- mark whether each female 48-58 admission has a hemorrhagic-stroke diagnosis
  SELECT
    f.*,
    IF(h.hadm_id IS NOT NULL, 1, 0) AS is_hem
  FROM female_hadm f
  LEFT JOIN hem_diag h
    ON f.hadm_id = h.hadm_id
),

lab_events AS (
  -- limit labevents to first 72 hours after admission for cohort admissions
  SELECT
    l.hadm_id,
    COALESCE(d.category, d.label) AS lab_system,
    l.valuenum,
    l.ref_range_lower,
    l.ref_range_upper,
    l.flag,
    l.charttime,
    hc.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN hadm_cohort hc
    ON l.hadm_id = hc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE l.charttime IS NOT NULL
    AND l.charttime >= hc.admittime
    AND l.charttime <= TIMESTAMP_ADD(hc.admittime, INTERVAL 72 HOUR)
),

lab_critical AS (
  -- flag as critical if flag text suggests critical/abnormal or valuenum outside ref ranges
  SELECT DISTINCT
    hadm_id,
    lab_system
  FROM lab_events
  WHERE (
      LOWER(IFNULL(flag, '')) LIKE '%crit%'
      OR LOWER(IFNULL(flag, '')) LIKE '%abnorm%'
    )
    OR (
      valuenum IS NOT NULL
      AND (
        (ref_range_lower IS NOT NULL AND valuenum < ref_range_lower)
        OR (ref_range_upper IS NOT NULL AND valuenum > ref_range_upper)
      )
    )
),

instability AS (
  -- instability score = number of distinct lab systems with >=1 critical result in first 72h
  SELECT
    hc.hadm_id,
    hc.is_hem,
    COUNT(lc.lab_system) AS instability_score,
    hc.hospital_expire_flag,
    hc.admittime,
    hc.dischtime
  FROM hadm_cohort hc
  LEFT JOIN lab_critical lc
    ON hc.hadm_id = lc.hadm_id
  GROUP BY hc.hadm_id, hc.is_hem, hc.hospital_expire_flag, hc.admittime, hc.dischtime
),

p90 AS (
  -- 90th percentile of instability score among hemorrhagic admissions (approximate)
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_value
  FROM instability
  WHERE is_hem = 1
),

metrics AS (
  SELECT
    p.p90_value,

    -- counts
    (SELECT COUNT(*) FROM instability WHERE is_hem = 1 AND instability_score >= p.p90_value) AS n_p90_patients,
    (SELECT COUNT(*) FROM instability WHERE is_hem = 1) AS n_hem_total,
    (SELECT COUNT(*) FROM instability WHERE is_hem = 0) AS n_age_matched_total,

    -- outcomes for hemorrhagic patients with instability_score >= P90
    (SELECT SAFE_DIVIDE(100.0 * SUM(hospital_expire_flag), COUNT(*))
     FROM instability
     WHERE is_hem = 1 AND instability_score >= p.p90_value) AS mortality_pct_p90,

    (SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, MINUTE) / 60.0 / 24.0)
     FROM instability
     WHERE is_hem = 1 AND instability_score >= p.p90_value AND dischtime IS NOT NULL) AS mean_los_days_p90,

    (SELECT AVG(instability_score)
     FROM instability
     WHERE is_hem = 1 AND instability_score >= p.p90_value) AS avg_critical_labs_per_patient_p90,

    -- comparison: average critical lab-systems per patient in age-matched female cohort WITHOUT hemorrhagic stroke
    (SELECT AVG(instability_score) FROM instability WHERE is_hem = 0) AS avg_critical_labs_per_patient_age_matched

  FROM p90 p
)

SELECT * FROM metrics;