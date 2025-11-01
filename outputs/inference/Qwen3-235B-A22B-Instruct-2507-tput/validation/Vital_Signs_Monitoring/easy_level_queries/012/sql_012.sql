WITH diastolic_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%diastolic%'
    AND LOWER(linksto) = 'chartevents'
),
per_stay_mean_bp AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS mean_diastolic_bp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN diastolic_items di ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 20 AND 120  -- plausible diastolic range
    AND LOWER(ce.valueuom) = 'mm hg'
    AND (
      LOWER(icu.first_careunit) LIKE '%step%'
      OR LOWER(icu.first_careunit) LIKE '%intermediate%'
      OR LOWER(icu.first_careunit) LIKE '%imc%'
      OR LOWER(icu.last_careunit) LIKE '%step%'
      OR LOWER(icu.last_careunit) LIKE '%intermediate%'
      OR LOWER(icu.last_careunit) LIKE '%imc%'
    )
  GROUP BY ce.stay_id
)
SELECT
  APPROX_QUANTILES(mean_diastolic_bp, 1000)[OFFSET(750)] -
  APPROX_QUANTILES(mean_diastolic_bp, 1000)[OFFSET(250)] AS iqr_mean_diastolic_bp
FROM per_stay_mean_bp;