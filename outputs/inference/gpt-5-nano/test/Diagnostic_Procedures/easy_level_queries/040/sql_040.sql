WITH target_population AS (
  -- Male patients aged 51-61 (using anchor_age as the age proxy)
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
),
ecg_counts AS (
  -- Count distinct ECG/telemetry procedure events per ICU stay (then per subject)
  SELECT icu.subject_id,
         COUNT(DISTINCT pe.starttime) AS cnt
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` AS pe
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON pe.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ecg%'
     OR LOWER(di.label) LIKE '%telemetry%'
  GROUP BY icu.subject_id
)
SELECT
  quantiles[OFFSET(25)] AS percentile_25
FROM (
  SELECT APPROX_QUANTILES(COALESCE(c.cnt, 0), 100) AS quantiles
  FROM target_population t
  LEFT JOIN ecg_counts c
    ON t.subject_id = c.subject_id
);