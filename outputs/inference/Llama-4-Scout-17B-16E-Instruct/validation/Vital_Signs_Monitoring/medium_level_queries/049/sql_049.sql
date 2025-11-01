WITH 
sbp_itemid AS (
  SELECT 
    itemid, 
    label 
  FROM 
    `physionet-data.mimiciv_3_1_icu.d_items` 
  WHERE 
    label LIKE '%Systolic Blood Pressure%'
),
sbp_data AS (
  SELECT 
    ic.stay_id, 
    ce.charttime, 
    ce.valuenum AS sbp 
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` ic 
    ON p.subject_id = ic.subject_id 
  JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ic.subject_id = ce.subject_id 
    AND ic.stay_id = ce.stay_id 
  JOIN 
    sbp_itemid si 
    ON ce.itemid = si.itemid 
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 38 AND 48
    AND ce.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 48 HOUR)
),
stay_sbp AS (
  SELECT 
    stay_id, 
    AVG(sbp) AS avg_sbp 
  FROM 
    sbp_data 
  GROUP BY 
    stay_id
)
SELECT 
  PERCENT_RANK() OVER (ORDER BY avg_sbp) * 100 AS percentile
FROM 
  stay_sbp
WHERE 
  stay_id = (
    SELECT 
      ic.stay_id 
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON p.subject_id = ic.subject_id 
    WHERE 
      p.anchor_age = 43 AND p.gender = 'F'
    LIMIT 1
  );