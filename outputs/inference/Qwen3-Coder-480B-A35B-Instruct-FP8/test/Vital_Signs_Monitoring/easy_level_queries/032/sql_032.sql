WITH cohort AS (
  SELECT DISTINCT p.subject_id
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
rr_itemids AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) LIKE '%respiratory rate%'
),
first_24hr_rr AS (
  SELECT 
    ce.subject_id,
    ce.stay_id,
    ce.valuenum
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN physionet-data.mimiciv_3_1_icu.icustays icu
    ON ce.stay_id = icu.stay_id
  JOIN cohort c
    ON ce.subject_id = c.subject_id
  JOIN rr_itemids rr
    ON ce.itemid = rr.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
)
SELECT MAX(valuenum) AS max_respiratory_rate
FROM first_24hr_rr;