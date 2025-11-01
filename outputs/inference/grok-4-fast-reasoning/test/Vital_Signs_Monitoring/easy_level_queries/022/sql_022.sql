WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age >= 48
    AND anchor_age <= 58
),
qualifying_stays AS (
  SELECT i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN qualifying_patients p
    ON i.subject_id = p.subject_id
),
stay_max_maps AS (
  SELECT s.stay_id, MAX(c.valuenum) AS max_map
  FROM qualifying_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON c.stay_id = s.stay_id
  WHERE c.itemid = 220052
    AND c.valuenum IS NOT NULL
  GROUP BY s.stay_id
)
SELECT AVG(max_map) AS avg_of_stay_max_map
FROM stay_max_maps;