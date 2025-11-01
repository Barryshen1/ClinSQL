WITH eligible_temps AS (
  SELECT 
    s.stay_id,
    AVG(c.valuenum) AS avg_temp
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` s
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    a.hadm_id = s.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    s.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON 
    c.stay_id = s.stay_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON 
    c.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM s.intime) - p.anchor_year + p.anchor_age) BETWEEN 67 AND 77
    AND c.charttime >= s.intime
    AND c.charttime <= TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR)
    AND c.charttime <= s.outtime
    AND di.category = 'Temperature'
    AND di.unitname = 'C'
    AND c.valuenum IS NOT NULL
  GROUP BY 
    s.stay_id
)
SELECT 
  CASE 
    WHEN COUNT(*) > 0 THEN (COUNTIF(avg_temp <= 36.0) * 100.0 / COUNT(*)) 
    ELSE NULL 
  END AS percentile
FROM 
  eligible_temps;