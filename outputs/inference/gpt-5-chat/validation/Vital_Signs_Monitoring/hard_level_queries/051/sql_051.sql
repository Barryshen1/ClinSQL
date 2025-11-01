WITH ischemic_stroke_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE (icd_version = 9 AND (
            icd_code LIKE '433%' OR
            icd_code LIKE '434%' OR
            icd_code = '436'
        ))
     OR (icd_version = 10 AND (
            icd_code LIKE 'I63%'
        ))
),
stroke_flag AS (
  SELECT DISTINCT di.subject_id, di.hadm_id, 1 AS is_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  INNER JOIN ischemic_stroke_codes isc
    ON di.icd_code = isc.icd_code AND di.icd_version = isc.icd_version
),
base_cohort AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    p.gender,
    p.anchor_age,
    adm.hospital_expire_flag,
    ie.intime,
    ie.outtime,
    TIMESTAMP_DIFF(ie.outtime, ie.intime, HOUR) AS icu_los_hrs,
    IFNULL(sf.is_stroke, 0) AS is_stroke
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON ie.subject_id = adm.subject_id AND ie.hadm_id = adm.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  LEFT JOIN stroke_flag sf
    ON ie.subject_id = sf.subject_id AND ie.hadm_id = sf.hadm_id
),
-- Here we simulate having a derived instability score and abnormal episodes in first 48h
-- Replace this with your actual derivation from chartevents
instability_scores AS (
  SELECT
    stay_id,
    RAND() * 10 AS score48h,  -- placeholder
    RAND() * 5 AS abn48h      -- placeholder
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
),
cohort_with_scores AS (
  SELECT
    b.*,
    s.score48h,
    s.abn48h
  FROM base_cohort b
  INNER JOIN instability_scores s
    ON b.stay_id = s.stay_id
  WHERE b.anchor_age BETWEEN 89 AND 99
    AND b.gender = 'M'
)
,
-- 95th percentile for male ischemic stroke ICU patients 89-99
stroke_percentile AS (
  SELECT
    APPROX_QUANTILES(score48h,100)[OFFSET(95)] AS p95_score
  FROM cohort_with_scores
  WHERE is_stroke = 1
),
-- Determine the 75th percentile (top quartile cutoff) across all male ICU patients 89-99
overall_q3 AS (
  SELECT
    APPROX_QUANTILES(score48h,4)[OFFSET(3)] AS q3_score
  FROM cohort_with_scores
),
top_quartile AS (
  SELECT c.*
  FROM cohort_with_scores c
  CROSS JOIN overall_q3 q
  WHERE c.score48h >= q.q3_score
),
summary AS (
  SELECT
    CASE WHEN is_stroke = 1 THEN 'Ischemic Stroke' ELSE 'General ICU' END AS group_name,
    COUNT(DISTINCT stay_id) AS N,
    AVG(score48h) AS mean_instability,
    AVG(abn48h) AS mean_abnormal_episodes,
    AVG(icu_los_hrs) AS mean_icu_los_hrs,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS hospital_mortality_rate
  FROM top_quartile
  GROUP BY group_name
)
SELECT
  sp.p95_score AS stroke_p95_score48h,
  s.*
FROM stroke_percentile sp
CROSS JOIN summary s
ORDER BY group_name;