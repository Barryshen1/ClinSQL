WITH first_spo2_per_stay AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    (ARRAY_AGG(ce.valuenum ORDER BY ce.charttime ASC LIMIT 1))[OFFSET(0)] AS first_spo2
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
    AND ce.hadm_id = icu.hadm_id
    AND ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND ce.charttime >= icu.intime
    AND ce.valuenum IS NOT NULL
    AND (
      LOWER(di.label) LIKE '%spo2%'
      OR LOWER(di.label) LIKE '%oxygen saturation%'
      OR LOWER(di.label) LIKE '%o2 sat%'
      OR LOWER(di.label) LIKE '%pulse oxim%'
      OR LOWER(di.label) LIKE '%oxy sat%'
    )
  GROUP BY icu.subject_id, icu.hadm_id, icu.stay_id
)

SELECT
  q.quantiles[OFFSET(25)] AS p25_spo2,
  q.quantiles[OFFSET(75)] AS p75_spo2,
  q.quantiles[OFFSET(75)] - q.quantiles[OFFSET(25)] AS iqr_spo2,
  cnt.n_stays_with_first_spo2
FROM (
  SELECT APPROX_QUANTILES(first_spo2, 100) AS quantiles
  FROM first_spo2_per_stay
  WHERE first_spo2 IS NOT NULL
) q
CROSS JOIN (
  SELECT COUNT(*) AS n_stays_with_first_spo2
  FROM first_spo2_per_stay
  WHERE first_spo2 IS NOT NULL
) cnt;