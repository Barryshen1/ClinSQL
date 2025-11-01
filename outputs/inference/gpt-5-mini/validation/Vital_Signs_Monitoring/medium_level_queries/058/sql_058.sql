WITH systolic_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
),

sbp_per_stay AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    AVG(ce.valuenum) AS avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = s.stay_id
  JOIN systolic_items it
    ON ce.itemid = it.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON p.subject_id = s.subject_id
  WHERE
    UPPER(p.gender) = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND ce.charttime IS NOT NULL
    AND ce.charttime >= s.intime
    AND ce.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 30    -- plausible lower bound for systolic BP
    AND ce.valuenum < 300   -- plausible upper bound for systolic BP
  GROUP BY s.subject_id, s.hadm_id, s.stay_id
)

SELECT
  120.0 AS target_sbp,
  COUNT(*) AS n_stays_in_cohort,
  SUM(CASE WHEN avg_sbp <= 120.0 THEN 1 ELSE 0 END) AS n_at_or_below_120,
  100.0 * SUM(CASE WHEN avg_sbp <= 120.0 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_inclusive
FROM sbp_per_stay;