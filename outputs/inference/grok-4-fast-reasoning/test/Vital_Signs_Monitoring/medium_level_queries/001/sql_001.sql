WITH sbp_measurements AS (
  SELECT 
    ce.stay_id,
    ce.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE 
    LOWER(di.label) LIKE '%systolic blood pressure%'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
),
sbp_avgs AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS avg_sbp
  FROM 
    sbp_measurements
  GROUP BY 
    stay_id
  HAVING 
    avg_sbp IS NOT NULL
)
SELECT 
  CASE 
    WHEN avg_sbp < 140 THEN '<140'
    WHEN avg_sbp < 160 THEN '140–159'
    ELSE '>=160'
  END AS sbp_bin,
  COUNT(DISTINCT icu.subject_id) AS patient_count
FROM 
  sbp_avgs s
INNER JOIN 
  `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON s.stay_id = icu.stay_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp.patients` p
  ON icu.subject_id = p.subject_id
WHERE 
  p.gender = 'F'
  AND p.anchor_age BETWEEN 45 AND 55
GROUP BY 
  sbp_bin
ORDER BY 
  sbp_bin;