WITH 
  -- Identify Troponin-T itemid
  troponin_t_item AS (
    SELECT itemid 
    FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
    WHERE label LIKE '%Troponin%'
  ),
  
  -- Get initial Troponin-T lab results for male patients aged 54-64
  troponin_t_results AS (
    SELECT 
      a.hadm_id,
      le.valuenum,
      ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY le.charttime) AS rn
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.labevents` le 
        ON a.hadm_id = le.hadm_id
    WHERE 
      p.gender = 'M' 
      AND p.anchor_age BETWEEN 54 AND 64
      AND le.itemid IN (SELECT itemid FROM troponin_t_item)
  )

SELECT 
  COUNT(valuenum) AS n,
  AVG(valuenum) AS mean,
  STDDEV(valuenum) AS stddev,
  MIN(valuenum) AS min,
  MAX(valuenum) AS max,
  APPROX_QUANTILES(valuenum, 1000)[501] AS median,
  APPROX_QUANTILES(valuenum, 1000)[251] AS p25,
  APPROX_QUANTILES(valuenum, 1000)[751] AS p75
FROM 
  troponin_t_results
WHERE 
  rn = 1 AND valuenum > 0.01;