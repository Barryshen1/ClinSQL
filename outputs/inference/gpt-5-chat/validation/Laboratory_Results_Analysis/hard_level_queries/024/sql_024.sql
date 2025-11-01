WITH cohort AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a USING (subject_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d USING (subject_id, hadm_id)
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND LOWER(dd.long_title) LIKE '%cardiac arrest%'
),
lab_scores AS (
  SELECT c.subject_id, c.hadm_id,
         COUNTIF(
           (l.flag IS NOT NULL AND LOWER(l.flag) = 'abnormal')
           OR (l.ref_range_lower IS NOT NULL AND l.valuenum < l.ref_range_lower)
           OR (l.ref_range_upper IS NOT NULL AND l.valuenum > l.ref_range_upper)
         ) AS score
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.subject_id = l.subject_id AND c.hadm_id = l.hadm_id
  WHERE l.charttime >= c.admittime
    AND l.charttime < DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
score_stats AS (
  SELECT PERCENTILE_CONT(score, 0.9) OVER() AS p90_score
  FROM lab_scores
  LIMIT 1
),
high_group AS (
  SELECT ls.subject_id, ls.hadm_id, ls.score, c.admittime, c.dischtime, c.hospital_expire_flag
  FROM lab_scores ls
  CROSS JOIN score_stats ss
  JOIN cohort c USING (subject_id, hadm_id)
  WHERE ls.score >= ss.p90_score
),
high_metrics AS (
  SELECT
    COUNT(*) AS high_count,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR)/24.0) AS mean_los_days,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(score) AS mean_abnormal_labs
  FROM high_group
),
all_metrics AS (
  SELECT AVG(score) AS mean_abnormal_labs_all
  FROM lab_scores
)
SELECT
  hm.high_count,
  hm.mean_los_days,
  hm.mortality_rate,
  hm.mean_abnormal_labs AS mean_abnormal_labs_high,
  am.mean_abnormal_labs_all
FROM high_metrics hm
CROSS JOIN all_metrics am;