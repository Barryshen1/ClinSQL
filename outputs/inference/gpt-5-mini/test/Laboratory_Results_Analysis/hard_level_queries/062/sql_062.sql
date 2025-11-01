WITH sepsis_admissions AS (
  -- female admissions aged 43-53 with any diagnosis whose long_title mentions "sepsis"
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id
   AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON di.icd_code = dic.icd_code
   AND di.icd_version = dic.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 43 AND 53
    AND LOWER(dic.long_title) LIKE '%sepsis%'
),

lab_counts AS (
  -- count "critical" lab events (here: flagged labs) in first 72 hours per admission
  SELECT
    sa.hadm_id,
    sa.subject_id,
    sa.admittime,
    sa.dischtime,
    sa.hospital_expire_flag,
    COUNT(l.labevent_id) AS critical_events
  FROM sepsis_admissions sa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON l.hadm_id = sa.hadm_id
   AND l.charttime BETWEEN sa.admittime AND TIMESTAMP_ADD(sa.admittime, INTERVAL 72 HOUR)
   -- pragmatic "critical" definition: flagged lab values (flag is present and non-empty)
   AND l.flag IS NOT NULL
   AND TRIM(l.flag) != ''
  GROUP BY
    sa.hadm_id,
    sa.subject_id,
    sa.admittime,
    sa.dischtime,
    sa.hospital_expire_flag
)

SELECT
  COUNT(*) AS cohort_size,
  -- 25th percentile (approximate) of critical event counts across admissions
  APPROX_QUANTILES(critical_events, 100)[OFFSET(25)] AS events_25th_percentile,
  ROUND(AVG(critical_events), 3) AS mean_critical_events_per_admission,
  ROUND(AVG(TIMESTAMP_DIFF(dischtime, admittime, MINUTE) / 1440.0), 3) AS mean_los_days,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)), 4) AS mortality_rate
FROM lab_counts;