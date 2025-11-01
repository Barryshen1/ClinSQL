WITH diastolic_bp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%diastolic%' AND LOWER(label) LIKE '%bp%'
),
eligible_stays AS (
  SELECT icu.subject_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 49 AND 59
    AND (
      LOWER(icu.first_careunit) LIKE '%stepdown%' 
      OR LOWER(icu.first_careunit) LIKE '%intermediate%' 
      OR LOWER(icu.first_careunit) LIKE '%imc%'
      OR LOWER(icu.last_careunit) LIKE '%stepdown%' 
      OR LOWER(icu.last_careunit) LIKE '%intermediate%' 
      OR LOWER(icu.last_careunit) LIKE '%imc%'
    )
),
mean_dbp_per_stay AS (
  SELECT
    es.stay_id,
    AVG(ce.valuenum) AS mean_diastolic_bp
  FROM eligible_stays es
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON es.subject_id = ce.subject_id
    AND es.stay_id = ce.stay_id
  WHERE ce.itemid IN (SELECT itemid FROM diastolic_bp_items)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 200
  GROUP BY es.stay_id
),
iqr_calc AS (
  SELECT
    quantiles[OFFSET(1)] AS q1,
    quantiles[OFFSET(3)] AS q3
  FROM (
    SELECT APPROX_QUANTILES(mean_diastolic_bp, 4) AS quantiles
    FROM mean_dbp_per_stay
  )
)
SELECT
  q1,
  q3,
  (q3 - q1) AS iqr_diastolic_bp
FROM iqr_calc;