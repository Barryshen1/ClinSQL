WITH eligible_stays AS (
  SELECT 
    icu.stay_id,
    icu.subject_id,
    icu.intime,
    pat.gender,
    EXTRACT(YEAR FROM icu.intime) - pat.anchor_year AS age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON 
    icu.subject_id = pat.subject_id
  WHERE 
    EXTRACT(YEAR FROM icu.intime) - pat.anchor_year BETWEEN 73 AND 83
),
spo2_data AS (
  SELECT 
    es.stay_id,
    cev.charttime,
    cev.valuenum
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` cev
  ON 
    es.stay_id = cev.stay_id
  CROSS JOIN 
    UNNEST([220277, 220339, 220277]) AS spo2_itemid  -- Standard SpO2 itemids
  WHERE 
    es.gender = 'M'
    AND cev.itemid = spo2_itemid
    AND cev.charttime >= es.intime
    AND cev.charttime <= TIMESTAMP_ADD(es.intime, INTERVAL 1 DAY)
    AND cev.valuenum IS NOT NULL
    AND cev.valuenum BETWEEN 0 AND 100
),
stay_means AS (
  SELECT 
    stay_id,
    AVG(valuenum) AS mean_spo2
  FROM 
    spo2_data
  GROUP BY 
    stay_id
  HAVING 
    COUNT(valuenum) >= 1  -- At least one reading
)
SELECT 
  PERCENT_RANK() OVER (ORDER BY mean_spo2) AS percentile_92
FROM 
  stay_means
WHERE 
  mean_spo2 = 92.0  -- Target value; adjust if exact match not needed (e.g., use subquery for <=92)
LIMIT 1;