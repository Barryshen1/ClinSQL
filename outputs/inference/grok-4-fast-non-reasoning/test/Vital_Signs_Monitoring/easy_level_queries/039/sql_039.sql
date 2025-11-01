WITH eligible_stays AS (
  SELECT 
    p.subject_id,
    i.stay_id,
    i.intime,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    i.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
    AND i.first_careunit IN (
      'SICU', 'CSRU', 'CCU', 'CVICU', 'TSICU', 'NICU', 
      'Medical ICU', 'Surgical ICU', 'Cardiac Care Unit', 
      'Coronary Care Unit', 'Trauma/Surgical ICU'
    )  -- ICU and step-down equivalents
),
first_rr AS (
  SELECT 
    es.subject_id,
    es.stay_id,
    c.valuenum AS first_respiratory_rate
  FROM 
    eligible_stays es
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` c
  ON 
    es.subject_id = c.subject_id
    AND es.stay_id = c.stay_id
    AND c.itemid = 618  -- Respiratory rate
    AND c.charttime >= es.intime
    AND c.valuenum IS NOT NULL
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY es.stay_id ORDER BY c.charttime ASC) = 1
)
SELECT 
  PERCENTILE_CONT(first_respiratory_rate, 0.25) AS p25_first_respiratory_rate
FROM 
  first_rr;