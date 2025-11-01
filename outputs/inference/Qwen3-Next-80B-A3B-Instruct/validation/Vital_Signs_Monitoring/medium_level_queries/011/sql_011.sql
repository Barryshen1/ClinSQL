WITH rr_measurements AS (
  SELECT 
    ie.stay_id,
    ie.charttime,
    ie.valuenum AS rr_value
  FROM physionet-data.mimiciv_3_1_icu.chartevents ie
  INNER JOIN physionet-data.mimiciv_3_1_icu.d_items di
    ON ie.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%respiratory rate%'
    AND ie.valuenum IS NOT NULL
    AND ie.valuenum > 0
),
first_48h_rr AS (
  SELECT 
    ie.stay_id,
    AVG(ie.rr_value) AS avg_rr
  FROM rr_measurements ie
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays icu
    ON ie.stay_id = icu.stay_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND ie.charttime >= icu.intime
    AND ie.charttime < icu.intime + INTERVAL '48' HOUR
  GROUP BY ie.stay_id
),
categorized AS (
  SELECT 
    CASE 
      WHEN avg_rr < 12 THEN '<12'
      WHEN avg_rr >= 12 AND avg_rr < 21 THEN '12–20'
      WHEN avg_rr >= 21 AND avg_rr < 30 THEN '21–29'
      WHEN avg_rr >= 30 THEN '≥30'
    END AS rr_category,
    avg_rr
  FROM first_48h_rr
  WHERE avg_rr IS NOT NULL
)
SELECT 
  rr_category,
  COUNT(*) AS n,
  AVG(avg_rr) AS mean,
  PERCENTILE_CONT(avg_rr, 0.5) AS median,
  PERCENTILE_CONT(avg_rr, 0.75) - PERCENTILE_CONT(avg_rr, 0.25) AS iqr
FROM categorized
WHERE rr_category IS NOT NULL
GROUP BY rr_category
ORDER BY 
  CASE rr_category
    WHEN '<12' THEN 1
    WHEN '12–20' THEN 2
    WHEN '21–29' THEN 3
    WHEN '≥30' THEN 4
  END;