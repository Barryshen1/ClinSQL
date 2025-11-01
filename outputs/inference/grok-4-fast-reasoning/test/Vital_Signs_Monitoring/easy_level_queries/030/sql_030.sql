WITH eligible_stays AS (
  SELECT ic.stay_id, ic.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ic
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ic.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
),
first_hr AS (
  SELECT es.stay_id, ce.valuenum AS hr_value
  FROM eligible_stays es
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ce.stay_id = es.stay_id
  WHERE ce.itemid = 220045
    AND ce.charttime >= es.intime
    AND ce.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY es.stay_id ORDER BY ce.charttime ASC) = 1
)
SELECT MIN(hr_value) AS min_first_hr
FROM first_hr;