WITH rr_per_stay AS (
  SELECT
    icu.stay_id,
    AVG(ce.valuenum) AS rr_avg
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON pat.subject_id = icu.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = icu.subject_id
   AND ce.hadm_id = icu.hadm_id
   AND ce.charttime >= icu.intime
   AND ce.charttime <= TIMESTAMP_ADD(icu.intime, INTERVAL 48 HOUR)
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
   -- target respiratory rate measurements (robust across label variations)
   AND (LOWER(di.label) LIKE '%respiratory rate%' OR LOWER(di.label) LIKE '%rr%')
  WHERE UPPER(pat.gender) = 'M'
    AND pat.anchor_age BETWEEN 54 AND 64
    AND ce.valuenum IS NOT NULL
  GROUP BY icu.stay_id
  HAVING rr_avg IS NOT NULL
),

rr_binned AS (
  SELECT
    CASE
      WHEN rr_avg < 12 THEN '<12'
      WHEN rr_avg >= 12 AND rr_avg < 21 THEN '12-20'
      WHEN rr_avg >= 21 AND rr_avg < 30 THEN '21-29'
      ELSE '>=30'
    END AS rr_bin,
    rr_avg
  FROM rr_per_stay
)

SELECT
  rr_bin,
  COUNT(*) AS n,
  AVG(rr_avg) AS mean_rr,
  APPROX_QUANTILES(rr_avg, 100)[OFFSET(50)] AS median_rr,
  APPROX_QUANTILES(rr_avg, 100)[OFFSET(25)] AS q1_rr,
  APPROX_QUANTILES(rr_avg, 100)[OFFSET(75)] AS q3_rr
FROM rr_binned
GROUP BY rr_bin
ORDER BY rr_bin;