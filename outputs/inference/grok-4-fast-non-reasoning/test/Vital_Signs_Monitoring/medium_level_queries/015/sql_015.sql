WITH icu_sbp AS (
  SELECT 
    icu.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.subject_id = icu.subject_id 
    AND adm.hadm_id = icu.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON icu.subject_id = ce.subject_id 
    AND icu.hadm_id = ce.hadm_id 
    AND icu.stay_id = ce.stay_id
  WHERE 
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 59 AND 69
    AND adm.admission_type = 'EMERGENCY'
    AND ce.itemid = 220045
    AND ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
  GROUP BY 
    icu.stay_id
  HAVING 
    max_sbp IS NOT NULL
)
SELECT 
  APPROX_QUANTILES(max_sbp, 4)[OFFSET(3)] AS p75_max_sbp
FROM 
  icu_sbp;