WITH hr_itemids AS (
  -- Identify heart rate itemids from d_items by label/abbreviation text matching
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
     OR LOWER(label) LIKE '%heartrate%'
     OR LOWER(COALESCE(abbreviation, '')) LIKE '%hr%'
),
per_stay AS (
  -- Per-ICU-stay mean heart rate for male patients age 40-50
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    AVG(ce.valuenum) AS mean_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ce.subject_id = p.subject_id
  JOIN hr_itemids h
    ON ce.itemid = h.itemid
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),
ordered AS (
  -- Order per-stay means and assign row numbers for median calculation
  SELECT
    mean_hr,
    ROW_NUMBER() OVER (ORDER BY mean_hr) AS rn
  FROM per_stay
),
cnt AS (
  SELECT COUNT(*) AS total FROM per_stay
)
-- Compute exact median: middle value for odd N, average of two middle for even N
SELECT
  CASE
    WHEN total = 0 THEN NULL
    WHEN MOD(total, 2) = 1 THEN (
      SELECT mean_hr FROM ordered WHERE rn = (total + 1) / 2
    )
    ELSE (
      (SELECT mean_hr FROM ordered WHERE rn = total / 2)
      +
      (SELECT mean_hr FROM ordered WHERE rn = total / 2 + 1)
    ) / 2.0
  END AS median_per_stay_mean_hr,
  total AS number_of_stays_considered
FROM cnt;