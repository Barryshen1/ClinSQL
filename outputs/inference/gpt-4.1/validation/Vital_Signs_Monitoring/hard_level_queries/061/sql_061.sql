with composite_score
WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    pat.gender,
    pat.anchor_age,
    icu.intime,
    icu.outtime,
    icu.los,
    adm.hospital_expire_flag,
    -- Assume composite_score is precomputed and available per stay
    -- Replace this with actual calculation if needed
    cs.composite_score
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON icu.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
      ON icu.hadm_id = adm.hadm_id
    -- Replace this with actual calculation if needed
    JOIN `physionet-data.mimiciv_3_1_icu.composite_scores` cs
      ON icu.stay_id = cs.stay_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 49 AND 59
)

-- 2. Compute percentile for score=70
, percentiles AS (
  SELECT
    composite_score,
    COUNT(*) AS n,
    SUM(CASE WHEN composite_score <= 70 THEN 1 ELSE 0 END) AS n_le_70,
    SUM(CASE WHEN composite_score > 70 THEN 1 ELSE 0 END) AS n_gt_70
  FROM cohort
)

-- 3. Get top decile (top 10% by composite_score)
, scored AS (
  SELECT
    *,
    NTILE(10) OVER (ORDER BY composite_score DESC) AS decile
  FROM cohort
)

SELECT
  -- Percentile for score=70
  SAFE_DIVIDE((SELECT n_le_70 FROM percentiles), (SELECT n FROM percentiles)) * 100 AS percentile_for_score_70,
  -- Mean ICU LOS (days) for top decile
  AVG(CASE WHEN decile = 1 THEN los ELSE NULL END) AS mean_icu_los_top_decile_days,
  -- Hospital mortality (%) for top decile
  SAFE_DIVIDE(SUM(CASE WHEN decile = 1 AND hospital_expire_flag = 1 THEN 1 ELSE 0 END), SUM(CASE WHEN decile = 1 THEN 1 ELSE 0 END)) * 100 AS hospital_mortality_top_decile_percent
FROM scored;