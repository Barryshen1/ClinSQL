WITH rr_per_stay AS (
  SELECT
    ce.stay_id,
    AVG(ce.valuenum) AS avg_rr
  FROM `physionet-data.mimiciv_3_1_icu`.chartevents ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON icu.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND LOWER(di.label) = 'respiratory rate'
    AND ce.charttime >= icu.intime
    AND ce.charttime < DATETIME_ADD(icu.intime, INTERVAL 48 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
),
rr_categories AS (
  SELECT
    avg_rr,
    CASE
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr BETWEEN 12 AND 20 THEN '12-20'
      WHEN avg_rr BETWEEN 21 AND 29 THEN '21-29'
      WHEN avg_rr >= 30 THEN '≥30'
    END AS rr_bin
  FROM rr_per_stay
)
SELECT
  rr_bin,
  COUNT(*) AS n,
  ROUND(AVG(avg_rr), 2) AS mean_avg_rr,
  ROUND(APPROX_QUANTILES(avg_rr, 100)[OFFSET(50)], 2) AS median_avg_rr,
  CONCAT(
    ROUND(APPROX_QUANTILES(avg_rr, 100)[OFFSET(25)], 2), '-',
    ROUND(APPROX_QUANTILES(avg_rr, 100)[OFFSET(75)], 2)
  ) AS iqr_avg_rr
FROM rr_categories
WHERE rr_bin IS NOT NULL
GROUP BY rr_bin
ORDER BY
  CASE rr_bin
    WHEN '<12' THEN 1
    WHEN '12-20' THEN 2
    WHEN '21-29' THEN 3
    WHEN '≥30' THEN 4
  END;