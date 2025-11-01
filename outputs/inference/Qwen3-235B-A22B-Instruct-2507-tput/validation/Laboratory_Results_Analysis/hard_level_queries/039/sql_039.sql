WITH cohort AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 60 AND 70
    AND di.seq_num = 1
    AND LOWER(d.long_title) LIKE '%pneumonia%'
),
lab_instability AS (
  SELECT 
    c.hadm_id,
    COUNT(*) AS abnormal_lab_count
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp`.labevents l ON c.hadm_id = l.hadm_id
  WHERE l.charttime >= c.admittime 
    AND l.charttime < DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag = 'abnormal'
  GROUP BY c.hadm_id
),
icu_stays_cohort AS (
  SELECT 
    c.hadm_id,
    COUNT(i.stay_id) AS icu_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON c.hadm_id = i.hadm_id
  GROUP BY c.hadm_id
),
all_male_60_70 AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 60 AND 70
),
icu_stays_all AS (
  SELECT 
    a.hadm_id,
    COUNT(i.stay_id) AS icu_count
  FROM all_male_60_70 a
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON a.hadm_id = i.hadm_id
  GROUP BY a.hadm_id
),
cohort_summary AS (
  SELECT
    APPROX_QUANTILES(COALESCE(l.abnormal_lab_count, 0), 100)[OFFSET(75)] AS p75_lab_instability_score,
    AVG(COALESCE(i.icu_count, 0)) AS mean_icu_stays_cohort,
    AVG(c.dischtime - c.admittime) AS avg_los_interval,
    AVG(c.hospital_expire_flag) AS hospital_mortality_rate
  FROM cohort c
  LEFT JOIN lab_instability l ON c.hadm_id = l.hadm_id
  LEFT JOIN icu_stays_cohort i ON c.hadm_id = i.hadm_id
),
population_summary AS (
  SELECT
    AVG(COALESCE(i.icu_count, 0)) AS mean_icu_stays_all
  FROM all_male_60_70 a
  LEFT JOIN icu_stays_all i ON a.hadm_id = i.hadm_id
)
SELECT
  cs.p75_lab_instability_score,
  cs.mean_icu_stays_cohort,
  ps.mean_icu_stays_all,
  EXTRACT(DAY FROM cs.avg_los_interval) + 
    EXTRACT(HOUR FROM cs.avg_los_interval) / 24.0 AS avg_los_days,
  cs.hospital_mortality_rate
FROM cohort_summary cs
CROSS JOIN population_summary ps;