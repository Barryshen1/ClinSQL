WITH eligible_stays AS (
  SELECT 
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 81 AND 91
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
      WHERE 
        pe.stay_id = i.stay_id
        AND pe.itemid = 226732
    )
)
SELECT MIN(mean_sbp) AS min_mean_sbp
FROM (
  SELECT 
    es.stay_id,
    AVG(c.valuenum) AS mean_sbp
  FROM eligible_stays es
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c 
    ON es.stay_id = c.stay_id
  WHERE 
    c.itemid = 220050
    AND c.charttime BETWEEN es.intime AND es.outtime
  GROUP BY es.stay_id
) AS means;