WITH
-- 1) Identify ACS admissions for male patients aged 87-97
acs_admissions AS (
  SELECT DISTINCT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag,
         p.anchor_age,
         p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- diagnosis joins to find ACS-related diagnoses by text match in the diagnosis dictionary
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
    -- pragmatic ACS keyword match in long_title to capture AMI/unstable angina/acute coronary syndromes
    AND LOWER(dd.long_title) LIKE '%acute%'
    AND (
         LOWER(dd.long_title) LIKE '%myocard%'   -- myocardial
      OR LOWER(dd.long_title) LIKE '%infarct%'  -- infarction
      OR LOWER(dd.long_title) LIKE '%angina%'   -- angina
      OR LOWER(dd.long_title) LIKE '%coronar%'  -- coronary
    )
    -- ensure valid admission times
    AND a.admittime IS NOT NULL
),

-- 2) For all admissions compute number of "critical" lab events in first 72 hours
lab_critical_counts AS (
  SELECT
    a.hadm_id,
    -- Count each labevent row that meets the critical criteria
    COUNT(*) AS critical_events_72h
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON l.hadm_id = a.hadm_id
  WHERE a.admittime IS NOT NULL
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    -- Define "critical" as numeric value outside ref range when available OR a flag indicating abnormal/critical
    AND (
      (l.valuenum IS NOT NULL
       AND (
         (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
         OR (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
       )
      )
      OR (
        -- check textual flags for abnormal/critical (case-insensitive, partial match)
        LOWER(COALESCE(l.flag, '')) LIKE '%abn%'   -- abnormal
        OR LOWER(COALESCE(l.flag, '')) LIKE '%crit%' -- critical
        OR LOWER(COALESCE(l.flag, '')) LIKE '%high%'
        OR LOWER(COALESCE(l.flag, '')) LIKE '%low%'
      )
    )
  GROUP BY a.hadm_id
),

-- 3) For all admissions, create a table with lab count (0 if none)
admission_lab_scores AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    COALESCE(lc.critical_events_72h, 0) AS lab_instability_72h
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN lab_critical_counts lc
    ON a.hadm_id = lc.hadm_id
  WHERE a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- 4) ACS male elderly admissions with their lab scores
acs_with_scores AS (
  SELECT ad.* 
  FROM admission_lab_scores ad
  JOIN acs_admissions acs
    ON ad.hadm_id = acs.hadm_id
),

-- 5) Compute P95 for the ACS cohort
p95_value AS (
  SELECT
    -- APPROX_QUANTILES(..., 100) returns an array with 101 values; OFFSET(95) is the 95th percentile
    (APPROX_QUANTILES(lab_instability_72h, 100))[OFFSET(95)] AS p95_lab_instability_72h
  FROM acs_with_scores
),

-- 6) ACS admissions at or above P95 with metrics
acs_highscore_metrics AS (
  SELECT
    p95.p95_lab_instability_72h,
    COUNT(*) AS n_admissions_at_or_above_p95,
    AVG( SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, MINUTE), 1440.0) ) AS mean_los_days,
    -- hospital_expire_flag is typically 0/1; take average to get proportion dead in hospital
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS inpatient_mortality_prop,
    AVG(lab_instability_72h) AS avg_critical_events_per_admission_in_cohort
  FROM acs_with_scores a
  CROSS JOIN p95_value p95
  WHERE a.lab_instability_72h >= p95.p95_lab_instability_72h
),

-- 7) General inpatients: average critical events per admission (same 72h window)
general_inpatient_metrics AS (
  SELECT
    COUNT(*) AS n_all_admissions,
    AVG(lab_instability_72h) AS avg_critical_events_per_admission_all_inpatients
  FROM admission_lab_scores
)

-- Final select: bring together P95, ACS-high metrics, and general inpatient comparison
SELECT
  p95.p95_lab_instability_72h AS p95_lab_instability_72h_among_male_age_87_97_with_ACS,
  ahs.n_admissions_at_or_above_p95,
  ahs.mean_los_days AS mean_los_days_for_p95_or_higher_admissions,
  ahs.inpatient_mortality_prop AS in_hospital_mortality_rate_for_p95_or_higher_admissions,
  ahs.avg_critical_events_per_admission_in_cohort AS avg_critical_events_per_admission_p95_plus_cohort,
  gim.avg_critical_events_per_admission_all_inpatients AS avg_critical_events_per_admission_all_inpatients
FROM p95_value p95
LEFT JOIN acs_highscore_metrics ahs
  ON TRUE
LEFT JOIN general_inpatient_metrics gim
  ON TRUE;