WITH systolic_items AS (
  -- Identify itemids that look like systolic BP measurements
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
),

per_stay_avg AS (
  -- Compute per-stay average systolic BP over the first 48 hours of each ICU stay
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    AVG(ce.valuenum) AS avg_systolic_first48
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.stay_id = icu.stay_id
  JOIN systolic_items si
    ON ce.itemid = si.itemid
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
    -- only measurements in first 48 hours after ICU intime
    AND ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
    -- numeric values only and reasonable physiologic range
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 40 AND 300
    -- ignore flagged/warninged measurements when possible
    AND ce.warning IS NULL
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
)

SELECT
  COUNT(*) AS n_stays_with_systolic_first48,
  SUM(CASE WHEN avg_systolic_first48 <= 160 THEN 1 ELSE 0 END) AS n_stays_avg_leq_160,
  ROUND(100.0 * SAFE_DIVIDE(SUM(CASE WHEN avg_systolic_first48 <= 160 THEN 1 ELSE 0 END), COUNT(*)), 2) AS percentile_of_160_inclusive
FROM per_stay_avg;