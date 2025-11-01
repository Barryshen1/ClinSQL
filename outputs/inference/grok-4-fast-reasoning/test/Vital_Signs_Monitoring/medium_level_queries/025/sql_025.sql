WITH qualifying_temps AS (
  SELECT 
    icu.stay_id,
    AVG(
      CASE 
        WHEN ce.valueuom = 'C' THEN ce.valuenum
        WHEN ce.valueuom = 'F' THEN (ce.valuenum - 32) * 5 / 9
        ELSE NULL 
      END
    ) AS avg_temp
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat 
    ON icu.subject_id = pat.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON icu.stay_id = ce.stay_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di 
    ON ce.itemid = di.itemid
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
    AND di.category = 'Temperature'
    AND ce.valuenum IS NOT NULL
    AND ce.valueuom IN ('C', 'F')
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY 
    icu.stay_id
  HAVING 
    COUNT(ce.itemid) > 0
    AND AVG(
      CASE 
        WHEN ce.valueuom = 'C' THEN ce.valuenum
        WHEN ce.valueuom = 'F' THEN (ce.valuenum - 32) * 5 / 9
        ELSE NULL 
      END
    ) IS NOT NULL
)
SELECT 
  CASE 
    WHEN COUNT(*) > 0 THEN (COUNTIF(avg_temp <= 37.5) * 100.0 / COUNT(*))
    ELSE 0 
  END AS percentile
FROM 
  qualifying_temps;