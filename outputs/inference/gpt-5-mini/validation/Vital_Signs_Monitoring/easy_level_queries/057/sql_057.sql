WITH rr_items AS (
  -- Identify itemids corresponding to respiratory rate
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
     OR LOWER(abbreviation) LIKE '%respiratory rate%'
     OR LOWER(label) LIKE '%resp rate%'
     OR LOWER(label) LIKE '%resp rate %'
),
rr_per_stay AS (
  -- For each ICU stay, compute the maximum respiratory rate observed during the stay
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    MAX(c.valuenum) AS max_rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN rr_items r
    ON c.itemid = r.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.subject_id = icu.subject_id
   AND c.hadm_id = icu.hadm_id
   AND c.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON c.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 35 AND 45
    AND c.valuenum IS NOT NULL
    -- ensure the measurement falls within the ICU stay window
    AND c.charttime BETWEEN icu.intime AND icu.outtime
    -- basic plausibility filter for respiratory rate
    AND c.valuenum > 0
    AND c.valuenum <= 150
  GROUP BY c.subject_id, c.hadm_id, c.stay_id
),
min_of_max AS (
  -- Compute the minimum of the per-stay maxima
  SELECT MIN(max_rr) AS min_of_max_rr
  FROM rr_per_stay
)
-- Return the minimum value and the stay(s) attaining that minimum for context
SELECT
  m.min_of_max_rr,
  r.subject_id,
  r.hadm_id,
  r.stay_id,
  r.max_rr
FROM min_of_max m
JOIN rr_per_stay r
  ON r.max_rr = m.min_of_max_rr
ORDER BY r.subject_id, r.hadm_id, r.stay_id;