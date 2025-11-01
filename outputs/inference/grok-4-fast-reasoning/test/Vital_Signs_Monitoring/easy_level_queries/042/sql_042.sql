WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' 
    AND anchor_age BETWEEN 63 AND 73
),
max_rr_per_patient AS (
  SELECT 
    qp.subject_id, 
    MAX(ce.valuenum) AS max_rr
  FROM qualifying_patients qp
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
    ON qp.subject_id = icu.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON icu.subject_id = ce.subject_id 
    AND icu.stay_id = ce.stay_id
    AND ce.itemid = 618
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
    AND ce.valuenum IS NOT NULL
  GROUP BY qp.subject_id
  HAVING max_rr IS NOT NULL
)
SELECT 
  STDDEV(max_rr) AS sd_max_respiratory_rate
FROM max_rr_per_patient;