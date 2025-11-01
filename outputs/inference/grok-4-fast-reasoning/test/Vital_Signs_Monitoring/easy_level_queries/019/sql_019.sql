WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 73 AND 83
),
qualifying_stays AS (
  SELECT i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN qualifying_patients qp
    ON i.subject_id = qp.subject_id
  WHERE i.first_careunit LIKE '%Stepdown%'
     OR i.first_careunit LIKE '%Step Down%'
     OR i.first_careunit LIKE '%IMC%'
     OR i.last_careunit LIKE '%Stepdown%'
     OR i.last_careunit LIKE '%Step Down%'
     OR i.last_careunit LIKE '%IMC%'
)
SELECT AVG(avg_map_per_stay) AS average_map_per_stay_mmhg
FROM (
  SELECT c.stay_id, AVG(c.valuenum) AS avg_map_per_stay
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN qualifying_stays qs
    ON c.stay_id = qs.stay_id
  WHERE c.itemid = 220052
    AND c.valuenum IS NOT NULL
  GROUP BY c.stay_id
);