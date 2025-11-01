WITH cohort AS (
  SELECT DISTINCT p.subject_id, p.anchor_age, p.gender, a.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i ON a.hadm_id = i.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND i.outtime IS NOT NULL
    AND (
      LOWER(d.long_title) LIKE '%intracranial hemorrhage%'
      OR LOWER(d.long_title) LIKE '%intracerebral hemorrhage%'
      OR (d.icd_code = '431' AND d.icd_version = 9)
      OR (d.icd_code LIKE 'I61%' AND d.icd_version = 10)
    )
),
cohort_outcomes AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.outtime,
    p.dod,
    -- 30-day mortality: death within 30 days of ICU discharge
    CASE WHEN p.dod IS NOT NULL AND DATETIME(p.dod) <= DATETIME_ADD(c.outtime, INTERVAL 30 DAY) 
         THEN 1 ELSE 0 END AS died_30d_post_icu,
    -- AKI diagnosis in same admission?
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code = 'N179' THEN 1
             WHEN di.icd_version = 9 AND di.icd_code = '5849' THEN 1
             ELSE 0 END) AS has_aki,
    -- ARDS diagnosis
    MAX(CASE WHEN di.icd_version = 10 AND di.icd_code = 'J80' THEN 1
             WHEN di.icd_version = 9 AND di.icd_code = '51882' THEN 1
             ELSE 0 END) AS has_ards,
    -- survival days after ICU discharge for decedents
    CASE WHEN p.dod IS NOT NULL THEN DATETIME_DIFF(p.dod, c.outtime, DAY) END AS days_survived_post_icu
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON c.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di ON c.hadm_id = di.hadm_id
  GROUP BY c.subject_id, c.hadm_id, c.outtime, p.dod
),
summary_stats AS (
  SELECT
    COUNT(*) AS cohort_size,
    AVG(died_30d_post_icu) AS mortality_30d_rate,
    AVG(has_aki) AS aki_rate,
    AVG(has_ards) AS ards_rate,
    CAST(NULL AS FLOAT64) AS composite_25th,
    CAST(NULL AS FLOAT64) AS composite_50th,
    CAST(NULL AS FLOAT64) AS composite_75th,
    APPROX_QUANTILES(CASE WHEN days_survived_post_icu IS NOT NULL THEN days_survived_post_icu END, 100)[OFFSET(50)] AS median_survival_decedents
  FROM cohort_outcomes
)
SELECT
  cohort_size,
  mortality_30d_rate,
  aki_rate,
  ards_rate,
  composite_25th,
  composite_50th,
  composite_75th,
  median_survival_decedents
FROM summary_stats;