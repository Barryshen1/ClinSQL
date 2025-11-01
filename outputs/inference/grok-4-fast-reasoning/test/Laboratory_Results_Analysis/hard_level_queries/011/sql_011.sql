WITH eligible_patients AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.gender,
    (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 47 AND 57
),
aki_flags AS (
  SELECT 
    hadm_id,
    MAX(CASE 
      WHEN icd_version = 9 AND icd_code LIKE '584%' THEN 1
      WHEN icd_version = 10 AND icd_code LIKE 'N17%' THEN 1
      ELSE 0 
    END) AS has_aki
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),
cohort AS (
  SELECT 
    e.*,
    COALESCE(ak.has_aki, 0) AS has_aki
  FROM eligible_patients e
  LEFT JOIN aki_flags ak 
    ON e.hadm_id = ak.hadm_id
),
icu_flags AS (
  SELECT DISTINCT 
    subject_id, 
    hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
cohort_with_icu AS (
  SELECT 
    c.*,
    CASE WHEN i.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_icu,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days
  FROM cohort c
  LEFT JOIN icu_flags i 
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id
),
lab_scores AS (
  SELECT 
    l.hadm_id,
    COUNT(*) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort_with_icu c 
    ON l.subject_id = c.subject_id 
    AND l.hadm_id = c.hadm_id 
    AND c.has_aki = 1
  WHERE l.charttime >= c.admittime 
    AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag <> ''
  GROUP BY l.hadm_id
),
cohort_final AS (
  SELECT 
    c.*,
    COALESCE(ls.instability_score, 0) AS instability_score
  FROM cohort_with_icu c
  LEFT JOIN lab_scores ls 
    ON c.hadm_id = ls.hadm_id
)
SELECT 
  AVG(CASE WHEN has_aki = 1 THEN instability_score END) AS mean_instability_score_aki,
  AVG(CASE WHEN has_aki = 1 THEN has_icu * 1.0 END) AS critical_event_freq_aki,
  AVG(CASE WHEN has_aki = 0 THEN has_icu * 1.0 END) AS critical_event_freq_control,
  AVG(CASE WHEN has_aki = 1 THEN los_days END) AS avg_los_aki,
  AVG(CASE WHEN has_aki = 0 THEN los_days END) AS avg_los_control,
  AVG(CASE WHEN has_aki = 1 THEN hospital_expire_flag * 1.0 END) AS mortality_rate_aki,
  AVG(CASE WHEN has_aki = 0 THEN hospital_expire_flag * 1.0 END) AS mortality_rate_control
FROM cohort_final;