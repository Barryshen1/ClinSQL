WITH temp_data AS (
  SELECT 
    ie.stay_id,
    AVG(
      CASE 
        WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9  -- Convert F to C
        ELSE ce.valuenum
      END
    ) AS mean_temp_c
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND ce.itemid IN (223761, 223762)  -- Temperature F and C
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN ie.intime AND ie.outtime
  GROUP BY ie.stay_id
  HAVING mean_temp_c IS NOT NULL
)
SELECT
  PERCENTILE_CONT(mean_temp_c, 0.75) OVER() AS percentile_75
FROM temp_data
LIMIT 1;