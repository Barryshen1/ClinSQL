WITH cohort AS (
  SELECT
    p.subject_id,
    i.stay_id,
    -- Simulating instability score; in practice, replace with real calculation
    ABS(RAND()) * 100 AS score,
    i.los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age >= 51
    AND p.anchor_age <= 61
)
SELECT
  (SELECT COUNT(*) FROM cohort WHERE score <= 80) * 100.0 / COUNT(*) AS percentile_of_80,
  AVG(CASE WHEN score >= score_90th THEN los END) AS avg_los_top_decile,
  AVG(CASE WHEN score >= score_90th THEN hospital_expire_flag END) AS mortality_top_decile
FROM cohort
CROSS JOIN (
  SELECT APPROX_QUANTILES(score, 1000)[OFFSET(900)] AS score_90th
  FROM cohort
) AS q;