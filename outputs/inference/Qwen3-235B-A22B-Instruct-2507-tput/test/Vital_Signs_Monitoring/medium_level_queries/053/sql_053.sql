WITH sbp_measurements AS (
  SELECT
    ce.valuenum AS sbp
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON p.subject_id = icu.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON icu.stay_id = ce.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di
    ON ce.itemid = di.itemid
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 65 AND 75
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
    AND LOWER(di.label) LIKE '%systolic%'
    AND LOWER(di.category) LIKE '%vital%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
),
sbp_categorized AS (
  SELECT
    sbp,
    CASE
      WHEN sbp < 140 THEN '<140'
      WHEN sbp >= 140 AND sbp < 160 THEN '140-159'
      WHEN sbp >= 160 THEN '≥160'
      ELSE NULL
    END AS sbp_category
  FROM sbp_measurements
)
SELECT
  sbp_category,
  ROUND(AVG(sbp), 2) AS mean_sbp,
  ROUND(APPROX_QUANTILES(sbp, 100)[OFFSET(50)], 2) AS median_sbp,
  ROUND(APPROX_QUANTILES(sbp, 100)[OFFSET(75)] - APPROX_QUANTILES(sbp, 100)[OFFSET(25)], 2) AS iqr_sbp
FROM sbp_categorized
WHERE sbp_category IS NOT NULL
GROUP BY sbp_category
ORDER BY
  CASE sbp_category
    WHEN '<140' THEN 1
    WHEN '140-159' THEN 2
    WHEN '≥160' THEN 3
  END;