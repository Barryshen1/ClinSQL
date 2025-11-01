WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    EXTRACT(YEAR FROM a.admittime) - 2008 + p.anchor_age AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM a.admittime) - 2008 + p.anchor_age) BETWEEN 53 AND 63
),
cohort_arrest AS (
  SELECT c.*
  FROM cohort c
  WHERE EXISTS (
    SELECT 1 
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    WHERE di.subject_id = c.subject_id
      AND di.hadm_id = c.hadm_id
      AND (
        (di.icd_version = 10 AND di.icd_code LIKE 'I46%')
        OR
        (di.icd_version = 9 AND di.icd_code = '427.5')
      )
  )
),
scores_cohort AS (
  SELECT 
    ca.hadm_id,
    ca.admittime,
    ca.dischtime,
    ca.hospital_expire_flag,
    COUNT(le.labevent_id) AS instability_score
  FROM cohort_arrest ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = ca.subject_id
    AND le.hadm_id = ca.hadm_id
    AND le.charttime >= ca.admittime
    AND le.charttime < TIMESTAMP_ADD(ca.admittime, INTERVAL 48 HOUR)
    AND le.flag <> ''
  GROUP BY 
    ca.hadm_id, 
    ca.admittime, 
    ca.dischtime, 
    ca.hospital_expire_flag
),
p90 AS (
  SELECT PERCENTILE_CONT(0.9) OVER (ORDER BY instability_score) AS p90_score
  FROM scores_cohort
  LIMIT 1
),
high_scores AS (
  SELECT 
    sc.hadm_id,
    sc.admittime,
    sc.dischtime,
    sc.hospital_expire_flag,
    sc.instability_score
  FROM scores_cohort sc
  CROSS JOIN p90 p
  WHERE sc.instability_score >= p.p90_score
),
stats_high AS (
  SELECT 
    COUNT(*) AS count_high,
    SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) AS mortality_high,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_high
  FROM high_scores
),
all_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
scores_all AS (
  SELECT 
    aa.hadm_id,
    COUNT(le.labevent_id) AS instability_score_all
  FROM all_admissions aa
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.subject_id = aa.subject_id
    AND le.hadm_id = aa.hadm_id
    AND le.charttime >= aa.admittime
    AND le.charttime < TIMESTAMP_ADD(aa.admittime, INTERVAL 48 HOUR)
    AND le.flag <> ''
  GROUP BY aa.hadm_id
),
freq_all AS (
  SELECT AVG(instability_score_all) AS critical_freq_all
  FROM scores_all
),
freq_high AS (
  SELECT AVG(instability_score) AS critical_freq_high
  FROM high_scores
)
SELECT 
  (SELECT p90_score FROM p90) AS p90_instability_score,
  (SELECT count_high FROM stats_high) AS count_high,
  (SELECT mortality_high FROM stats_high) AS mortality_high,
  (SELECT mean_los_high FROM stats_high) AS mean_los_high,
  (SELECT critical_freq_high FROM freq_high) AS critical_freq_high,
  (SELECT critical_freq_all FROM freq_all) AS critical_freq_all;