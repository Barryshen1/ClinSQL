WITH discharge_day_potassium AS (
  SELECT 
    l.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i ON l.hadm_id = i.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON l.hadm_id = a.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON l.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND d.itemid = 50822
    AND DATE(l.charttime) = DATE(a.dischtime)
)
SELECT 
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS potassium_75th_percentile
FROM 
  discharge_day_potassium;