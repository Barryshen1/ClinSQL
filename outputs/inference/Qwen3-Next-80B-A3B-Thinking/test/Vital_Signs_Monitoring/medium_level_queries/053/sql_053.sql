WITH filtered_icu AS (
  SELECT
    i.stay_id,
    i.intime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 65 AND 75
)
SELECT
  bp_category,
  AVG(valuenum) AS mean,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS median,
  (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - 
   PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum)) AS iqr
FROM (
  SELECT
    c.valuenum,
    CASE
      WHEN c.valuenum < 140 THEN '<140'
      WHEN c.valuenum >= 140 AND c.valuenum <= 159 THEN '140-159'
      ELSE '>=160'
    END AS bp_category
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN filtered_icu f
    ON c.stay_id = f.stay_id
  WHERE c.itemid IN (220050, 220179)
    AND c.charttime >= f.intime
    AND c.charttime <= f.intime + INTERVAL 24 HOUR
    AND c.valuenum IS NOT NULL
) AS categorized_data
GROUP BY bp_category;