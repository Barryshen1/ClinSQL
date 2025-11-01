WITH cohort AS (
  SELECT
    i.stay_id,
    i.hadm_id,
    i.los,
    a.hospital_expire_flag,
    -- Placeholder for instability score (would be calculated from first 48h data in real analysis)
    0 AS instability_score
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON i.hadm_id = a.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 81 AND 91
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
      WHERE ce.stay_id = i.stay_id
        AND ce.itemid = 227287  -- High Flow Oxygen Device
        AND ce.charttime BETWEEN i.intime AND DATETIME_ADD(i.intime, INTERVAL 48 HOUR)
        AND ce.value IS NOT NULL
    )
),
cohort_with_decile AS (
  SELECT *,
    NTILE(10) OVER (ORDER BY instability_score DESC) AS decile
  FROM cohort
)
SELECT
  (SELECT COUNT(*) FROM cohort WHERE instability_score <= 85) * 100.0 / COUNT(*) AS percentile_85,
  (SELECT AVG(los) FROM cohort_with_decile WHERE decile = 1) AS avg_los_top_decile,
  (SELECT AVG(hospital_expire_flag) FROM cohort_with_decile WHERE decile = 1) * 100 AS mortality_pct_top_decile
FROM cohort;