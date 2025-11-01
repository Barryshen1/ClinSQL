WITH sbp_max_per_stay AS (
  SELECT 
    i.stay_id,
    MAX(ce.valuenum) AS max_sbp
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.patients p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a 
      ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i 
      ON a.hadm_id = i.hadm_id AND p.subject_id = i.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce 
      ON i.stay_id = ce.stay_id
    INNER JOIN `physionet-data.mimiciv_3_1_icu`.d_items di 
      ON ce.itemid = di.itemid
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 59 AND 69
    AND UPPER(a.admission_location) LIKE '%EMERGENCY%'
    AND UPPER(di.label) IN ('SYSTOLIC BP', 'SYSTOLIC ARTERIAL PRESSURE', 'ARTERIAL BP SYSTOLIC', 'BP SYSTOLIC', 'Systolic BP')
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300
  GROUP BY 
    i.stay_id
)
SELECT 
  PERCENTILE_CONT(max_sbp, 0.75) AS p75_max_sbp
FROM 
  sbp_max_per_stay;