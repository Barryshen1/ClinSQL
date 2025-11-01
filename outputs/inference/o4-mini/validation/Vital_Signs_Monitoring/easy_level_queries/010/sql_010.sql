WITH female_cohort AS (
  SELECT
    p.subject_id,
    icustay.stay_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icustay
      ON p.subject_id = icustay.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 71 AND 81
),

diastolic_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%diastolic%'
    AND LOWER(label) LIKE '%blood pressure%'
),

per_stay_max_dbp AS (
  SELECT
    fc.stay_id,
    MAX(ce.valuenum) AS max_dbp
  FROM
    female_cohort AS fc
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON fc.stay_id = ce.stay_id
  WHERE
    ce.itemid IN (SELECT itemid FROM diastolic_items)
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom = 'mmHg'
  GROUP BY
    fc.stay_id
)

SELECT
  quantiles[OFFSET(50)] AS median_per_stay_max_dbp
FROM (
  SELECT
    APPROX_QUANTILES(max_dbp, 100) AS quantiles
  FROM
    per_stay_max_dbp
);