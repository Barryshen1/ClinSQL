WITH cohort AS (
  SELECT 
    icu.subject_id, 
    icu.stay_id, 
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON icu.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year) BETWEEN 82 AND 92
),
temp_events AS (
  SELECT 
    c.stay_id,
    CASE 
      WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9  -- Convert F to C
      ELSE ce.valuenum
    END AS temp_c
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND c.subject_id = ce.subject_id
  WHERE 
    ce.itemid IN (220734, 223761, 223762, 223765, 223763, 223764, 223766, 223767, 223768, 223769, 223770, 223771, 223772)  -- Temp items
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- Exclude non-physiological values
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)  -- First 24h of ICU stay
),
per_stay_avg AS (
  SELECT 
    stay_id,
    AVG(temp_c) AS avg_temp
  FROM temp_events
  GROUP BY stay_id
)
SELECT 
  COUNT(*) AS total_stays,
  SUM(CASE WHEN avg_temp <= 37.5 THEN 1 ELSE 0 END) AS count_below,
  ROUND(
    (SUM(CASE WHEN avg_temp <= 37.5 THEN 1 ELSE 0 END) * 100.0) / COUNT(*),
    2
  ) AS percentile
FROM per_stay_avg;