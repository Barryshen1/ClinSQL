WITH bp_measurements AS (
  SELECT
    ce.subject_id,
    isi.hadm_id,
    isi.stay_id,
    ce.charttime,
    ce.valuenum AS bp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS isi
    ON ce.stay_id = isi.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON ce.subject_id = p.subject_id
  WHERE
    LOWER(di.label) LIKE '%blood%' AND LOWER(di.label) LIKE '%systolic%'
    AND ce.charttime >= isi.intime
    AND ce.charttime <= TIMESTAMP_ADD(isi.intime, INTERVAL 24 HOUR)
    AND LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 65 AND 75
    AND ce.valuenum IS NOT NULL
)
SELECT
  CASE
    WHEN bp < 140 THEN '<140'
    WHEN bp >= 140 AND bp <= 159 THEN '140-159'
    WHEN bp >= 160 THEN '>=160'
  END AS bp_category,
  AVG(bp) AS mean_bp,
  (APPROX_QUANTILES(bp, 2)[OFFSET(1)]) AS median_bp,
  (APPROX_QUANTILES(bp, 4)[OFFSET(3)] - APPROX_QUANTILES(bp, 4)[OFFSET(1)]) AS iqr_bp
FROM bp_measurements
GROUP BY bp_category
ORDER BY bp_category;