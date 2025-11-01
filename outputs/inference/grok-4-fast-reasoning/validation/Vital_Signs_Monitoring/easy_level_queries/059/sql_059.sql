WITH first_spo2 AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    i.stay_id,
    c.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i 
    ON p.subject_id = i.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON i.subject_id = c.subject_id 
    AND i.stay_id = c.stay_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    AND c.itemid = 220277
    AND c.valuenum IS NOT NULL
    AND c.valueuom = '%'
    AND c.charttime >= i.intime
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY i.stay_id ORDER BY c.charttime ASC) = 1
)
SELECT 
  STDDEV(valuenum) AS stddev_first_spo2
FROM 
  first_spo2;