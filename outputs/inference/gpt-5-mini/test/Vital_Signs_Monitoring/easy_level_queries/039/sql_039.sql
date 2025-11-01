WITH resp_items AS (
  -- respiratory rate itemids: use common label patterns (case-insensitive)
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%respiratory rate%' OR
    LOWER(label) LIKE '%resp rate%' OR
    LOWER(label) LIKE '%respiratory%' AND LOWER(label) LIKE '%rate%'
),

first_rr_per_stay AS (
  -- pick the first respiratory rate charted at or after ICU intime for each stay
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime,
    CAST(c.valuenum AS FLOAT64) AS rr,
    c.charttime,
    ROW_NUMBER() OVER (PARTITION BY i.stay_id ORDER BY c.charttime, c.storetime) AS rn
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON i.subject_id = c.subject_id
   AND i.hadm_id = c.hadm_id
   AND i.stay_id = c.stay_id
  JOIN resp_items r
    ON c.itemid = r.itemid
  WHERE
    c.charttime IS NOT NULL
    AND c.charttime >= i.intime
    AND c.valuenum IS NOT NULL
    -- keep plausible respiratory rates to reduce noise
    AND c.valuenum BETWEEN 5 AND 60
),

first_rr_filtered AS (
  -- keep only the first RR per ICU stay
  SELECT subject_id, hadm_id, stay_id, rr, charttime
  FROM first_rr_per_stay
  WHERE rn = 1
)

SELECT
  -- approximate 25th percentile (quartile) of the first respiratory rates
  APPROX_QUANTILES(rr, 100)[OFFSET(25)] AS rr_25th_percentile,
  COUNT(*) AS n_first_rr_in_cohort
FROM first_rr_filtered f
JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON f.subject_id = p.subject_id
WHERE
  p.gender = 'F'
  AND p.anchor_age BETWEEN 51 AND 61;