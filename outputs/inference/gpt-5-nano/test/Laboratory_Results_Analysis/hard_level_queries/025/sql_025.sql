WITH eligible AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  WHERE
    p.gender = 'F'
    AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%')
    AND p.anchor_age BETWEEN 48 AND 58
),

-- 2) Lab events within first 72 hours, annotate if a value is critical
lab_events AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    li.category AS lab_system,
    CASE
      WHEN le.valuenum IS NOT NULL
           AND (
             (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
             OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
           )
           OR (
             IFNULL(le.flag, '') LIKE '%CRIT%'
             OR LOWER(IFNULL(le.flag, '')) LIKE '%critical%'
           )
      THEN 1
      ELSE 0
    END AS is_critical
  FROM eligible AS e
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    ON le.hadm_id = e.hadm_id
   AND le.subject_id = e.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
    ON li.itemid = le.itemid
  WHERE le.charttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 72 HOUR)
),

-- 3) Per-admission lab-system critical counts (score)
lab_scores AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    -- Count distinct lab systems with critical values within the first 72h
    COUNT(DISTINCT CASE
      WHEN s.is_critical = 1 AND s.lab_system IS NOT NULL THEN s.lab_system
      END) AS lab_systems_with_critical
  FROM lab_events AS s
  GROUP BY s.subject_id, s.hadm_id
),

-- 4) 90th percentile of the lab-instability score across eligible admissions
p90 AS (
  SELECT quantiles[OFFSET(90)] AS p90
  FROM (
    SELECT APPROX_QUANTILES(ls.lab_systems_with_critical, 101) AS quantiles
    FROM lab_scores AS ls
  ) t
),

-- 5) Enrich eligible admissions with their scores
scored AS (
  SELECT
    e.subject_id,
    e.hadm_id,
    e.admittime,
    e.dischtime,
    e.hospital_expire_flag,
    COALESCE(ls.lab_systems_with_critical, 0) AS lab_systems_with_critical
  FROM eligible AS e
  LEFT JOIN lab_scores AS ls
    ON ls.subject_id = e.subject_id
   AND ls.hadm_id = e.hadm_id
),

-- 6) Define high-risk and non-high-risk cohorts
high_risk AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.admittime,
    s.dischtime,
    s.hospital_expire_flag,
    s.lab_systems_with_critical
  FROM scored AS s
  CROSS JOIN p90
  WHERE s.lab_systems_with_critical >= p90.p90
),

non_high_risk AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.admittime,
    s.dischtime,
    s.hospital_expire_flag,
    s.lab_systems_with_critical
  FROM scored AS s
  CROSS JOIN p90
  WHERE s.lab_systems_with_critical < p90.p90
)

-- 7) Final reporting: mortality %, mean LOS, and avg critical labs per patient
SELECT
  'High-risk (>= P90)' AS cohort_label,
  ROUND(100.0 * SUM(CASE WHEN hr.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percent,
  AVG(TIMESTAMP_DIFF(hr.dischtime, hr.admittime, SECOND) / 86400.0) AS mean_los_days,
  AVG(hr.lab_systems_with_critical) AS avg_critical_lab_systems
FROM high_risk AS hr

UNION ALL

SELECT
  'Age-matched non-high-risk (< P90)' AS cohort_label,
  ROUND(100.0 * SUM(CASE WHEN nh.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percent,
  AVG(TIMESTAMP_DIFF(nh.dischtime, nh.admittime, SECOND) / 86400.0) AS mean_los_days,
  AVG(nh.lab_systems_with_critical) AS avg_critical_lab_systems
FROM non_high_risk AS nh
ORDER BY cohort_label;