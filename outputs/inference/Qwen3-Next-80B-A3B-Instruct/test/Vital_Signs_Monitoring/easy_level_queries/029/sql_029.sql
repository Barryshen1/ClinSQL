WITH first_spo2 AS (
  SELECT 
    p.subject_id,
    ce.valuenum,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY ce.charttime) AS rn
  FROM 
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.chartevents ce
    ON p.subject_id = ce.subject_id
  INNER JOIN 
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    AND di.label = 'SpO2'
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum >= 0
    AND ce.valuenum <= 100
)
SELECT 
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS iqr
FROM 
  first_spo2
WHERE 
  rn = 1;