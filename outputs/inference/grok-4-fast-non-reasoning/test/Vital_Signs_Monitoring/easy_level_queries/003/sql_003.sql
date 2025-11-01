WITH stay_hr AS (
  SELECT 
    icu.stay_id,
    AVG(ce.valuenum) AS mean_hr_per_stay
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON 
    icu.subject_id = pat.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    icu.subject_id = ce.subject_id 
    AND icu.stay_id = ce.stay_id
  WHERE 
    pat.anchor_age BETWEEN 40 AND 50
    AND pat.gender = 'M'
    AND ce.itemid = 220045
    AND ce.valuenum IS NOT NULL 
    AND ce.valuenum > 0
    AND ce.charttime >= icu.intime 
    AND ce.charttime <= icu.outtime
  GROUP BY 
    icu.stay_id
  HAVING 
    mean_hr_per_stay IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(mean_hr_per_stay, 2)[OFFSET(1)] AS median_mean_hr
FROM 
  stay_hr;