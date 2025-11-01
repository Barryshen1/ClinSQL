WITH cohort AS (
  -- Male ICU patients age 78–88 with a sepsis diagnosis
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON icu.subject_id = a.subject_id
   AND icu.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON icu.subject_id = d.subject_id
   AND icu.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
    ON d.icd_code = ddi.icd_code
   AND d.icd_version = ddi.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND LOWER(ddi.long_title) LIKE '%sepsis%'
),
first24_scores AS (
  -- Instability scores in the first 24h
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.los,
    s.score,
    s.score_time
  FROM cohort c
  JOIN `your_project.your_dataset.instability_scores` s  -- ← QUALIFIED
    ON c.stay_id = s.stay_id
  WHERE s.score_time BETWEEN c.intime
                        AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
),
one_score_per_stay AS (
  -- If there are multiple, take the earliest within 24h
  SELECT
    stay_id,
    subject_id,
    hadm_id,
    intime,
    los,
    score,
    score_time,
    ROW_NUMBER() OVER (PARTITION BY stay_id ORDER BY score_time) AS rn
  FROM first24_scores
),
scored AS (
  -- Keep only one score per stay, assign quartiles, and bring in mortality flag
  SELECT
    o.stay_id,
    o.subject_id,
    o.hadm_id,
    o.intime,
    o.los,
    o.score,
    NTILE(4) OVER (ORDER BY o.score) AS quartile,
    a2.hospital_expire_flag
  FROM one_score_per_stay o
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON o.hadm_id = a2.hadm_id
  WHERE o.rn = 1
)
-- Final aggregation
SELECT
  -- Percentile rank of a score of 85
  ROUND(
    100.0 * SUM(CASE WHEN score <= 85 THEN 1 ELSE 0 END) / COUNT(*)
  , 2) AS percentile_rank_score_85,
  -- Mean ICU LOS for quartile 4
  ROUND(
    AVG(CASE WHEN quartile = 4 THEN los END)
  , 2) AS mean_icu_los_q4,
  -- Hospital mortality rate for quartile 4
  ROUND(
    100.0 * AVG(CASE WHEN quartile = 4 THEN CAST(hospital_expire_flag AS FLOAT64) END)
  , 2) AS hosp_mortality_pct_q4
FROM scored;