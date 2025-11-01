WITH diastolic_items AS (
  -- ICU diastolic BP related items
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%diastolic%'
),
stay_means AS (
  -- Per-stay mean diastolic BP for the specified cohort
  SELECT
    icu.stay_id,
    icu.subject_id,
    AVG(ce.valuenum) AS mean_diastolic
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.itemid IN (SELECT itemid FROM diastolic_items)
    AND (LOWER(p.gender) IN ('m', 'male'))
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      LOWER(icu.first_careunit) LIKE '%step%'
      OR LOWER(icu.last_careunit) LIKE '%step%'
      OR LOWER(icu.first_careunit) LIKE '%imc%'
      OR LOWER(icu.last_careunit) LIKE '%imc%'
    )
  GROUP BY icu.stay_id, icu.subject_id
)
SELECT
  -- IQR = Q3 - Q1 from per-stay mean diastolic BP
  q[OFFSET(1)] AS q1_diastolic_mean,
  q[OFFSET(3)] AS q3_diastolic_mean,
  q[OFFSET(3)] - q[OFFSET(1)] AS iqr_diastolic_mean
FROM (
  SELECT APPROX_QUANTILES(mean_diastolic, 4) AS q
  FROM stay_means
) t;