WITH patient_icu_stays AS (
  SELECT 
    s.stay_id,
    s.intime,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM s.intime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON s.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND s.intime IS NOT NULL
    AND p.anchor_age IS NOT NULL
    AND p.anchor_year IS NOT NULL
),
temperature_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%'
    AND LOWER(unitname) LIKE '%c%'  -- ensure Celsius
),
stay_temps AS (
  SELECT 
    p.stay_id,
    AVG(CAST(c.valuenum AS FLOAT64)) AS avg_temp_24h,
    p.age_at_admission
  FROM patient_icu_stays p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON p.stay_id = c.stay_id
  INNER JOIN temperature_items t
    ON c.itemid = t.itemid
  WHERE c.charttime >= p.intime
    AND c.charttime < DATETIME_ADD(p.intime, INTERVAL 24 HOUR)
    AND c.valuenum IS NOT NULL
    AND c.valuenum BETWEEN 30 AND 43  -- physiologically plausible range
  GROUP BY p.stay_id, p.age_at_admission
  HAVING AVG(c.valuenum) IS NOT NULL
),
percentile_calc AS (
  SELECT
    COUNT(*) AS total_stays,
    COUNTIF(avg_temp_24h < 36.0) AS count_below,
    COUNTIF(ABS(avg_temp_24h - 36.0) < 0.001) AS count_equal
  FROM stay_temps
  WHERE age_at_admission >= 67 AND age_at_admission <= 77
)
SELECT
  (count_below + 0.5 * count_equal) / total_stays * 100 AS percentile
FROM percentile_calc;