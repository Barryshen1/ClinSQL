WITH temp_data AS (
  SELECT 
    ie.stay_id,
    AVG(
      CASE 
        WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9  -- Convert F to C
        ELSE ce.valuenum
      END
    ) AS avg_temp_c
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 67 AND 77
    AND ce.charttime BETWEEN ie.intime AND DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (223762, 223761)  -- Temperature C (223762) and Temperature F (223761)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 30 AND 45  -- Plausible range for Celsius
    AND ce.valuenum BETWEEN 86 AND 113  -- Plausible range for Fahrenheit (to avoid mixing units incorrectly)
  GROUP BY ie.stay_id
  HAVING avg_temp_c IS NOT NULL
),
percentiles AS (
  SELECT 
    avg_temp_c,
    PERCENT_RANK() OVER (ORDER BY avg_temp_c) AS percentile_rank
  FROM temp_data
)
SELECT 
  percentile_rank
FROM percentiles
WHERE avg_temp_c = 36.0
LIMIT 1;