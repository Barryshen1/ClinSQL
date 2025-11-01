WITH spo2_averages AS (
  SELECT 
    icu.stay_id,
    AVG(ce.valuenum) AS avg_spo2
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id 
    AND icu.hadm_id = ce.hadm_id 
    AND icu.stay_id = ce.stay_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 80 AND 90
    AND ce.itemid = 220277
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 0 AND 100
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
    AND icu.los > 0
  GROUP BY 
    icu.stay_id
  HAVING 
    COUNT(ce.valuenum) > 0
)

SELECT 
  COUNTIF(avg_spo2 <= 88) * 100.0 / COUNT(*) AS percentile
FROM 
  spo2_averages;