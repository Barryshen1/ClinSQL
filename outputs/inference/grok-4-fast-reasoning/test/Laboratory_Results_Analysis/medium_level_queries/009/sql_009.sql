WITH initial_hstnt AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    le.charttime, 
    le.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON le.hadm_id = a.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
    ON le.itemid = dli.itemid
  WHERE 
    p.gender = 'F'
    AND LOWER(dli.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
    AND le.charttime >= a.admittime
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 59 AND 69
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY a.subject_id, a.hadm_id ORDER BY le.charttime ASC) = 1
)
SELECT 
  MIN(valuenum) AS min_hstnt,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS p25_hstnt,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(2)] AS p50_hstnt,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS p75_hstnt,
  MAX(valuenum) AS max_hstnt,
  COUNT(*) AS n_admissions
FROM initial_hstnt
WHERE valuenum > 0.014;