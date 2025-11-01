WITH 
  -- Identify the itemid for mean arterial pressure (MAP)
  map_itemid AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_icu.d_items` 
    WHERE label = 'Mean Arterial Pressure'
  ),

  -- Filter the data for male patients aged 39-49 and calculate the average MAP for the first 24 hours of ICU stay
  patient_map AS (
    SELECT 
      p.subject_id,
      ic.stay_id,
      AVG(CASE 
            WHEN c.itemid = (SELECT itemid FROM map_itemid) AND 
                 c.charttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 24 HOUR) 
            THEN c.valuenum 
          END) AS avg_map
    FROM 
      `physionet-data.mimiciv_3_1_hosp.patients` p
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic ON p.subject_id = ic.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_icu.chartevents` c ON ic.stay_id = c.stay_id
    WHERE 
      p.gender = 'M' AND 
      p.anchor_age BETWEEN 39 AND 49
    GROUP BY 
      p.subject_id, ic.stay_id
  )

-- Calculate the percentile of the average MAP
SELECT 
  NTILE(100) OVER (ORDER BY avg_map) AS percentile
FROM 
  patient_map
WHERE 
  avg_map = 75;