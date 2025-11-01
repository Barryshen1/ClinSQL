WITH
-- identify admissions that have a hemorrhagic-stroke diagnosis
hemorrhagic_hadms AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    -- match by textual description when available
    (LOWER(COALESCE(dd.long_title, '')) LIKE '%hemorrh%' 
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%intracerebral%' 
     OR LOWER(COALESCE(dd.long_title, '')) LIKE '%subarachnoid%')
    -- or by common ICD code prefixes (ICD-9 and ICD-10)
    OR (d.icd_version = 9 AND (STARTS_WITH(d.icd_code, '430') OR STARTS_WITH(d.icd_code, '431') OR STARTS_WITH(d.icd_code, '432')))
    OR (d.icd_version = 10 AND (STARTS_WITH(UPPER(d.icd_code), 'I60') OR STARTS_WITH(UPPER(d.icd_code), 'I61') OR STARTS_WITH(UPPER(d.icd_code), 'I62')))
),

-- base admissions with LOS and patient characteristics
admissions_base AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- LOS in days as fractional value
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR), 24.0) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),

-- compute per-admission first-48-hour lab instability counts
hadm_instability AS (
  -- compute is_crit per lab row within first 48h, then aggregate per hadm_id
  SELECT
    ab.hadm_id,
    SUM(IF(is_crit, 1, 0)) AS instability_count,
    -- whether there was at least one critical lab
    CASE WHEN SUM(IF(is_crit, 1, 0)) > 0 THEN 1 ELSE 0 END AS instability_any
  FROM admissions_base ab
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = ab.hadm_id
    AND le.charttime IS NOT NULL
    AND le.charttime BETWEEN ab.admittime AND TIMESTAMP_ADD(ab.admittime, INTERVAL 48 HOUR)
  -- determine if a lab row is "critical"
  CROSS JOIN UNNEST([STRUCT(
    CASE
      WHEN le.labevent_id IS NULL THEN FALSE
      WHEN (le.valuenum IS NOT NULL AND (
            (le.ref_range_lower IS NOT NULL AND le.valuenum < le.ref_range_lower)
            OR (le.ref_range_upper IS NOT NULL AND le.valuenum > le.ref_range_upper)
           )) THEN TRUE
      WHEN LOWER(COALESCE(le.flag, '')) LIKE '%abnorm%' THEN TRUE
      WHEN LOWER(COALESCE(le.flag, '')) LIKE '%crit%' THEN TRUE
      ELSE FALSE
    END AS is_crit
  )]) AS computed
  GROUP BY ab.hadm_id
),

-- combine admissions with instability info and patient/demo info
admissions_with_stats AS (
  SELECT
    ab.subject_id,
    ab.hadm_id,
    ab.admittime,
    ab.dischtime,
    ab.hospital_expire_flag,
    ab.los_days,
    COALESCE(hi.instability_count, 0) AS instability_count,
    COALESCE(hi.instability_any, 0) AS instability_any
  FROM admissions_base ab
  LEFT JOIN hadm_instability hi USING (hadm_id)
),

-- identify cohort admissions: male, age 70-80, and hemorrhagic stroke diagnosis on that admission
cohort_admissions AS (
  SELECT a.*
  FROM admissions_with_stats a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN hemorrhagic_hadms h
    ON a.hadm_id = h.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 70 AND 80
),

-- aggregated metrics for the hemorrhagic cohort
cohort_metrics AS (
  SELECT
    'hemorrhagic_cohort' AS group_name,
    COUNT(1) AS n_admissions,
    SUM(instability_any) AS n_with_crit_event,
    SAFE_DIVIDE(SUM(instability_any), COUNT(1)) AS crit_event_rate,
    -- 25th percentile of instability_count computed via a scalar subquery over cohort_admissions
    (
      SELECT quantiles[OFFSET(25)]
      FROM (
        SELECT APPROX_QUANTILES(instability_count, 100) AS quantiles
        FROM cohort_admissions
      )
    ) AS instability_25pct,
    AVG(los_days) AS mean_los_days,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1)) AS inhospital_mortality_rate
  FROM cohort_admissions
),

-- aggregated metrics for the general inpatient population (all admissions)
general_metrics AS (
  SELECT
    'general_inpatient' AS group_name,
    COUNT(1) AS n_admissions,
    SUM(instability_any) AS n_with_crit_event,
    SAFE_DIVIDE(SUM(instability_any), COUNT(1)) AS crit_event_rate,
    NULL AS instability_25pct,  -- not requested for general cohort (set NULL)
    AVG(los_days) AS mean_los_days,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(1)) AS inhospital_mortality_rate
  FROM admissions_with_stats
)

-- final unioned result: cohort vs general
SELECT * FROM cohort_metrics
UNION ALL
SELECT * FROM general_metrics
ORDER BY group_name;