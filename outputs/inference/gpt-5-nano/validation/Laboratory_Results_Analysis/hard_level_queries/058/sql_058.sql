WITH ACS_female_40_50 AS (
  SELECT a.subject_id,
         a.hadm_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag,
         a.deathtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id
   AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'Female'
    AND p.anchor_age BETWEEN 40 AND 50
    AND (LOWER(dd.long_title) LIKE '%myocardial%' OR LOWER(dd.long_title) LIKE '%unstable angina%')
),
LAB_SCORE AS (
  SELECT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         a.hospital_expire_flag,
         a.deathtime,
         SUM(CASE WHEN le.valuenum IS NOT NULL
                   AND le.ref_range_lower IS NOT NULL
                   AND le.ref_range_upper IS NOT NULL
                   AND (le.valuenum < le.ref_range_lower OR le.valuenum > le.ref_range_upper)
                   THEN 1 ELSE 0 END) AS instability_score,
         SUM(CASE WHEN LOWER(COALESCE(le.flag,'')) LIKE '%critical%' THEN 1 ELSE 0 END) AS critical_lab_count,
         COUNT(*) AS total_lab_count
  FROM ACS_female_40_50 a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = a.hadm_id
   AND le.charttime >= a.admittime
   AND le.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY a.hadm_id,
           a.subject_id,
           a.admittime,
           a.dischtime,
           a.hospital_expire_flag,
           a.deathtime
),
ACS_results AS (
  SELECT s.hadm_id,
         s.subject_id,
         s.admittime,
         s.dischtime,
         s.hospital_expire_flag,
         s.deathtime,
         s.instability_score,
         s.critical_lab_count,
         s.total_lab_count,
         (CASE WHEN s.hospital_expire_flag = 1 OR s.deathtime IS NOT NULL THEN 1 ELSE 0 END) AS death_flag,
         TIMESTAMP_DIFF(s.dischtime, s.admittime, SECOND) / 86400.0 AS los_days,
         (CASE WHEN s.total_lab_count > 0
               THEN CAST(s.critical_lab_count AS FLOAT64) / CAST(s.total_lab_count AS FLOAT64)
               ELSE 0 END) AS critical_rate
  FROM LAB_SCORE s
),
THRESH AS (
  SELECT quantiles[OFFSET(90)] AS thresh
  FROM (
    SELECT APPROX_QUANTILES(instability_score, 100) AS quantiles
    FROM ACS_results
  )
),
THRESH_VALUE AS (
  SELECT thresh FROM THRESH
),
JOINED AS (
  SELECT r.*,
         t.thresh AS thresh_value
  FROM ACS_results r CROSS JOIN THRESH_VALUE t
)
SELECT
  thresh_value AS score_90th_percentile,
  SUM(CASE WHEN instability_score >= thresh_value THEN death_flag ELSE NULL END)
    / NULLIF(SUM(CASE WHEN instability_score >= thresh_value THEN 1 ELSE 0 END), 0) AS high_group_death_rate,
  SUM(CASE WHEN instability_score >= thresh_value THEN los_days ELSE NULL END)
    / NULLIF(SUM(CASE WHEN instability_score >= thresh_value THEN 1 ELSE 0 END), 0) AS high_group_mean_los_days,
  SUM(CASE WHEN instability_score >= thresh_value THEN critical_rate ELSE NULL END)
    / NULLIF(SUM(CASE WHEN instability_score >= thresh_value THEN 1 ELSE 0 END), 0) AS high_group_critical_lab_rate,
  AVG(death_flag) AS general_death_rate_all,
  AVG(los_days) AS general_mean_los_days_all,
  AVG(critical_rate) AS general_critical_lab_rate_all
FROM JOINED
GROUP BY thresh_value;