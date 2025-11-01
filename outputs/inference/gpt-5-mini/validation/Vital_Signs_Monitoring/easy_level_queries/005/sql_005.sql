WITH systolic_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE (
    LOWER(label) LIKE '%systolic%'
    OR LOWER(abbreviation) LIKE '%sbp%'
    OR LOWER(label) LIKE '%systolic bp%'
    OR LOWER(label) LIKE '%arterial systolic%'
  )
),
female_age59_69 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 59 AND 69
)
SELECT
  APPROX_QUANTILES(ce.valuenum, 100)[OFFSET(75)] AS systolic_bp_p75,
  COUNT(1) AS measurement_count
FROM
  `physionet-data.mimiciv_3_1_icu.chartevents` ce
JOIN
  female_age59_69 p ON ce.subject_id = p.subject_id
JOIN
  systolic_items si ON ce.itemid = si.itemid
WHERE
  ce.valuenum IS NOT NULL
  AND ce.valuenum > 0
  AND ce.valuenum < 300;