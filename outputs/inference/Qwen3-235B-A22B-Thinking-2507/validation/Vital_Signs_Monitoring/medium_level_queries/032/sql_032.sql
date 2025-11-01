WITH eligible_patients AS (
  SELECT 
    p.subject_id,
    a.hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 53 AND 63
),
stepdown_admissions AS (
  SELECT DISTINCT
    e.subject_id,
    e.hadm_id
  FROM 
    eligible_patients e
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp`.transfers t
    ON e.subject_id = t.subject_id AND e.hadm_id = t.hadm_id
  WHERE 
    t.careunit = 'Stepdown Unit (SDU)'
),
ventilated_stays AS (
  SELECT DISTINCT
    s.subject_id,
    s.hadm_id,
    i.stay_id
  FROM 
    stepdown_admissions s
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu`.icustays i
    ON s.subject_id = i.subject_id AND s.hadm_id = i.hadm_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu`.procedureevents p
    ON i.stay_id = p.stay_id
  WHERE 
    p.itemid = 225468
),
nighttime_sbp AS (
  SELECT 
    c.valuenum AS sbp
  FROM 
    ventilated_stays vs
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu`.chartevents c
    ON vs.stay_id = c.stay_id
  WHERE 
    c.itemid IN (220050, 220179, 227243)
    AND c.valuenum IS NOT NULL
    AND c.valueuom = 'mmHg'
    AND EXTRACT(TIME FROM c.charttime) >= '00:00:00'
    AND EXTRACT(TIME FROM c.charttime) < '06:00:00'
)
SELECT 
  STDDEV(sbp) AS sbp_stddev
FROM 
  nighttime_sbp;