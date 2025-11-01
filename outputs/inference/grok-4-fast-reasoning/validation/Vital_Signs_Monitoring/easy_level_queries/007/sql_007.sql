WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' 
    AND anchor_age BETWEEN 73 AND 83
),
eligible_stays AS (
  SELECT stay_id, intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_patients ep 
    ON i.subject_id = ep.subject_id
),
first_rr AS (
  SELECT es.stay_id, ce.valuenum
  FROM eligible_stays es
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ce.stay_id = es.stay_id
  WHERE ce.itemid = 618 
    AND ce.valuenum IS NOT NULL 
    AND ce.charttime >= es.intime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY es.stay_id ORDER BY ce.charttime ASC) = 1
)
SELECT STDDEV(valuenum) AS sd_respiratory_rate
FROM first_rr;