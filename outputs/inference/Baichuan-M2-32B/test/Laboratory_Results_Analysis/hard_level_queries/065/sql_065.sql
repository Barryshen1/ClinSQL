WITH
  -- Step 1: Identify eligible admissions (women 65-75 with lower GI bleed diagnosis)
  eligible_admissions AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      -- Calculate age at admission using anchor_year and anchor_age
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE
      p.gender = 'F'
      AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 65 AND 75
      AND d.icd_version = 10
      AND d.icd_code IN ('K52.2', 'K52.3', 'K52.8', 'K62.8', 'K92.2') -- ICD-10 codes for lower GI bleed
  ),
  -- Step 2: Define critical lab itemids (Hemoglobin, Potassium, Sodium, Creatinine, Lactate)
  critical_labs AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
    WHERE 
      (label LIKE '%hemoglobin%' OR label LIKE '%potassium%' OR label LIKE '%sodium%' OR label LIKE '%creatinine%' OR label LIKE '%lactate%')
      AND category IN ('Blood Gas', 'Chemistry', 'Hematology')
  ),
  -- Step 3: Lab events for eligible admissions in first 72 hours
  cohort_labs AS (
    SELECT
      a.hadm_id,
      l.labevent_id,
      l.valuenum,
      l.ref_range_lower,
      l.ref_range_upper
    FROM eligible_admissions a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.hadm_id = l.hadm_id
    INNER JOIN critical_labs c
      ON l.itemid = c.itemid
    WHERE
      l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
      AND l.valuenum IS NOT NULL
      AND l.ref_range_lower IS NOT NULL
      AND l.ref_range_upper IS NOT NULL
  ),
  -- Step 4: Identify abnormal labs (outside reference range)
  cohort_abnormal_labs AS (
    SELECT
      hadm_id,
      labevent_id
    FROM cohort_labs
    WHERE
      (valuenum < ref_range_lower) OR (valuenum > ref_range_upper)
  ),
  -- Step 5: Instability score per admission (count of abnormal labs)
  instability_scores AS (
    SELECT
      a.hadm_id,
      COUNT(b.labevent_id) AS instability_score
    FROM eligible_admissions a
    LEFT JOIN cohort_abnormal_labs b
      ON a.hadm_id = b.hadm_id
    GROUP BY a.hadm_id
  ),
  -- Step 6: 25th percentile of instability score
  percentile_instability AS (
    SELECT
      PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY instability_score) AS percentile_25
    FROM instability_scores
  ),
  -- Step 7: Critical lab event frequency for cohort (proportion with ≥1 abnormal lab)
  cohort_critical_event_rate AS (
    SELECT
      COUNT(DISTINCT a.hadm_id) AS total_admissions,
      COUNT(DISTINCT CASE WHEN b.labevent_id IS NOT NULL THEN a.hadm_id END) AS admissions_with_event,
      COUNT(DISTINCT CASE WHEN b.labevent_id IS NOT NULL THEN a.hadm_id END) * 1.0 / COUNT(DISTINCT a.hadm_id) AS critical_event_rate
    FROM eligible_admissions a
    LEFT JOIN cohort_abnormal_labs b
      ON a.hadm_id = b.hadm_id
  ),
  -- Step 8: General cohort (women 65-75 without lower GI bleed diagnosis)
  general_admissions AS (
    SELECT
      a.subject_id,
      a.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
    WHERE
      p.gender = 'F'
      AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 65 AND 75
      AND a.hadm_id NOT IN (SELECT hadm_id FROM eligible_admissions) -- Exclude cohort admissions
  ),
  -- Step 9: Lab events for general cohort in first 72 hours
  general_labs AS (
    SELECT
      a.hadm_id,
      l.labevent_id,
      l.valuenum,
      l.ref_range_lower,
      l.ref_range_upper
    FROM general_admissions a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.hadm_id = l.hadm_id
    INNER JOIN critical_labs c
      ON l.itemid = c.itemid
    WHERE
      l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
      AND l.valuenum IS NOT NULL
      AND l.ref_range_lower IS NOT NULL
      AND l.ref_range_upper IS NOT NULL
  ),
  -- Step 10: Abnormal labs for general cohort
  general_abnormal_labs AS (
    SELECT
      hadm_id,
      labevent_id
    FROM general_labs
    WHERE
      (valuenum < ref_range_lower) OR (valuenum > ref_range_upper)
  ),
  -- Step 11: Critical lab event frequency for general cohort
  general_critical_event_rate AS (
    SELECT
      COUNT(DISTINCT a.hadm_id) AS total_admissions,
      COUNT(DISTINCT CASE WHEN b.labevent_id IS NOT NULL THEN a.hadm_id END) AS admissions_with_event,
      COUNT(DISTINCT CASE WHEN b.labevent_id IS NOT NULL THEN a.hadm_id END) * 1.0 / COUNT(DISTINCT a.hadm_id) AS critical_event_rate
    FROM general_admissions a
    LEFT JOIN general_abnormal_labs b
      ON a.hadm_id = b.hadm_id
  ),
  -- Step 12: LOS and mortality for cohort
  cohort_los_mortality AS (
    SELECT
      AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
      SUM(CAST(hospital_expire_flag AS INT)) * 1.0 / COUNT(*) AS mortality_rate
    FROM eligible_admissions
  )

-- Final output
SELECT
  p.percentile_25 AS percentile_25_instability_score,
  c.critical_event_rate AS cohort_critical_lab_event_rate,
  g.critical_event_rate AS general_cohort_critical_lab_event_rate,
  l.avg_los_days,
  l.mortality_rate
FROM percentile_instability p
CROSS JOIN cohort_critical_event_rate c
CROSS JOIN general_critical_event_rate g
CROSS JOIN cohort_los_mortality l;