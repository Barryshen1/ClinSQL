WITH cohort AS (
  -- Base cohort: male, 39-49, LOS 1-7 days
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

acs_base AS (
  -- Base for ACS flagging with diagnoses
  SELECT 
    c.*,
    di.seq_num,
    di.icd_code,
    di.icd_version
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.subject_id = di.subject_id AND c.hadm_id = di.hadm_id
),

acs_flags AS (
  -- Flag primary/secondary ACS using diagnoses
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    gender,
    anchor_age,
    los_days,
    CASE 
      WHEN seq_num = 1 AND (
        (icd_version = '9' AND REGEXP_CONTAINS(icd_code, r'^410')) OR
        (icd_version = '10' AND REGEXP_CONTAINS(icd_code, r'^I21|I22'))
      ) THEN 1  -- Primary ACS
      WHEN (
        (icd_version = '9' AND REGEXP_CONTAINS(icd_code, r'^410')) OR
        (icd_version = '10' AND REGEXP_CONTAINS(icd_code, r'^I21|I22'))
      ) AND seq_num > 1 AND NOT EXISTS (
        SELECT 1 FROM acs_base ab_primary
        WHERE ab_primary.subject_id = acs_flags.subject_id
          AND ab_primary.hadm_id = acs_flags.hadm_id
          AND ab_primary.seq_num = 1
          AND (
            (ab_primary.icd_version = '9' AND REGEXP_CONTAINS(ab_primary.icd_code, r'^410')) OR
            (ab_primary.icd_version = '10' AND REGEXP_CONTAINS(ab_primary.icd_code, r'^I21|I22'))
          )
      ) THEN 2  -- Secondary ACS
      ELSE 0  -- No ACS
    END AS acs_type
  FROM acs_base
),

filtered_cohort AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    gender,
    anchor_age,
    los_days,
    MAX(acs_type) AS acs_type  -- Max to get 1 or 2 if present
  FROM acs_flags
  WHERE acs_type > 0  -- Only include admissions with ACS
  GROUP BY subject_id, hadm_id, admittime, dischtime, gender, anchor_age, los_days
),

los_strata AS (
  -- Add LOS and ACS strata
  SELECT 
    *,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      ELSE '5-7 days'
    END AS los_group,
    CASE 
      WHEN acs_type = 1 THEN 'Primary ACS'
      ELSE 'Secondary ACS'
    END AS acs_group
  FROM filtered_cohort
),

ultrasound_procs AS (
  -- Identify ultrasound/echo procedures per admission
  SELECT 
    ls.subject_id,
    ls.hadm_id,
    ls.los_group,
    ls.acs_group,
    pi.icd_code,
    pi.icd_version
  FROM los_strata ls
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
    ON ls.subject_id = pi.subject_id AND ls.hadm_id = pi.hadm_id
  WHERE (
    (pi.icd_version = '9' AND (
      REGEXP_CONTAINS(pi.icd_code, r'^37\.0[1-9]')  -- Cardiac echo (ICD-9: 37010-37019)
      OR REGEXP_CONTAINS(pi.icd_code, r'^88\.7')     -- Diagnostic ultrasound (vascular, etc.)
    ))
    OR (pi.icd_version = '10' AND (
      REGEXP_CONTAINS(pi.icd_code, r'^4A02[3]')      -- Echocardiography (e.g., 4A023N7Z)
      OR REGEXP_CONTAINS(pi.icd_code, r'^BW4')        -- Ultrasound imaging (e.g., BW40, BW41)
    ))
  )
),

ultrasound_counts AS (
  -- Count distinct ultrasound procedures per admission
  SELECT 
    subject_id,
    hadm_id,
    los_group,
    acs_group,
    COUNT(DISTINCT pi.icd_code) AS ultrasound_count
  FROM ultrasound_procs
  GROUP BY subject_id, hadm_id, los_group, acs_group
),

agg_counts AS (
  -- Aggregate counts across admissions for percentiles
  SELECT 
    los_group,
    acs_group,
    ultrasound_count
  FROM ultrasound_counts
)

-- Final percentiles (p25=25th, p50=median, p75=75th)
SELECT 
  los_group,
  acs_group,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(1)] AS p25,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(2)] AS p50,
  APPROX_QUANTILES(ultrasound_count, 4)[OFFSET(3)] AS p75
FROM agg_counts
GROUP BY los_group, acs_group
ORDER BY los_group, acs_group;