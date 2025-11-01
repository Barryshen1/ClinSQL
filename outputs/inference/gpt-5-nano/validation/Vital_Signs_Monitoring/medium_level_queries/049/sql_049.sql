WITH cohort AS (
  -- Identify female patients aged 38-48 and their ICU stays
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = icu.subject_id
  WHERE UPPER(p.gender) = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
bp_items AS (
  -- For each stay, compute average systolic BP over the first 48 hours
  SELECT
    c.stay_id,
    AVG(e.valuenum) AS avg_sbp_48h
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS e
    ON e.stay_id = c.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON e.itemid = di.itemid
  WHERE e.charttime >= c.intime
    AND e.charttime < TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
    AND e.valuenum IS NOT NULL
    -- Identify systolic blood pressure readings robustly
    AND LOWER(di.label) LIKE '%systolic%'
    AND LOWER(di.label) LIKE '%blood%'
  GROUP BY c.stay_id
)
SELECT
  -- Percentile (0-100) of per-stay average SBP <= 130
  100.0 * SAFE_DIVIDE(
    SUM(CASE WHEN avg_sbp_48h <= 130 THEN 1 ELSE 0 END),
    COUNT(*)                             -- total number of stays in cohort with SBP data
  ) AS percentile_of_130
FROM bp_items;