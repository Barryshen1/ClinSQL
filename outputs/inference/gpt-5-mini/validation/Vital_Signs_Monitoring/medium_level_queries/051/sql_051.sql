WITH hr_itemids AS (
  -- Identify heart rate itemids from ICU d_items
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%heart rate%'
),

icu_male_age AS (
  -- ICU stays for male patients aged 55-65
  SELECT icu.*
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 55 AND 65
),

subject_max_hr AS (
  -- For each subject, compute the maximum heart rate observed during any ICU stay
  SELECT
    ce.subject_id,
    MAX(ce.valuenum) AS max_hr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN hr_itemids h
    ON ce.itemid = h.itemid
  JOIN icu_male_age icu
    ON ce.stay_id = icu.stay_id
       AND ce.subject_id = icu.subject_id
       -- ensure the charttime falls within the ICU stay interval
       AND ce.charttime BETWEEN icu.intime AND icu.outtime
  WHERE ce.valuenum IS NOT NULL
    -- plausible physiologic range for heart rate to reduce obvious artifacts
    AND ce.valuenum BETWEEN 30 AND 300
  GROUP BY ce.subject_id
)

SELECT
  q.arr[OFFSET(1)] AS q1_hr,
  q.arr[OFFSET(3)] AS q3_hr,
  SAFE_CAST(q.arr[OFFSET(3)] - q.arr[OFFSET(1)] AS FLOAT64) AS iqr_hr,
  (SELECT COUNT(*) FROM subject_max_hr) AS n_subjects
FROM (
  SELECT APPROX_QUANTILES(max_hr, 4) AS arr
  FROM subject_max_hr
) q
;