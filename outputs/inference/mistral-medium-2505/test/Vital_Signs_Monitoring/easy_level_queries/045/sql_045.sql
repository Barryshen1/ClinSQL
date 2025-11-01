WITH
-- Get the correct itemid for respiratory rate from d_items
respiratory_rate_item AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label = 'Respiratory Rate'
  LIMIT 1
),

-- Filter for males aged 51-61 in the ICU
target_patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    i.stay_id,
    i.intime AS icu_intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),

-- Get the first recorded respiratory rate for each patient in the ICU
first_respiratory_rate AS (
  SELECT
    t.subject_id,
    t.stay_id,
    c.valuenum AS respiratory_rate,
    ROW_NUMBER() OVER (PARTITION BY t.subject_id, t.stay_id ORDER BY c.charttime) AS rn
  FROM target_patients t
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON t.subject_id = c.subject_id AND t.stay_id = c.stay_id
  JOIN respiratory_rate_item r
    ON c.itemid = r.itemid
  WHERE c.valuenum IS NOT NULL
)

-- Calculate the standard deviation of the first respiratory rate
SELECT
  STDDEV(respiratory_rate) AS sd_first_respiratory_rate
FROM first_respiratory_rate
WHERE rn = 1;