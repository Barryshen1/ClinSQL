WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    l.charttime,
    l.valuenum,
    l.valueuom
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.subject_id = l.subject_id AND a.hadm_id = l.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 54 AND 64
    AND l.itemid = 3654
    AND l.valueuom = 'ng/mL'
    AND l.valuenum IS NOT NULL
    AND l.charttime >= a.admittime
),
first_troponin AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC) AS rn
  FROM cohort
)
SELECT 
  COUNT(*) AS n,
  AVG(valuenum) AS mean,
  STDDEV_SAMP(valuenum) AS sd,
  MIN(valuenum) AS min_val,
  MAX(valuenum) AS max_val,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75
FROM first_troponin
WHERE rn = 1 AND valuenum > 0.01;