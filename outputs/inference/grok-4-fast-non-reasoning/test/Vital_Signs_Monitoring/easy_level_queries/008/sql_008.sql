WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),
icu_stays AS (
  SELECT subject_id, stay_id, hadm_id, intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  WHERE subject_id IN (SELECT subject_id FROM eligible_patients)
    AND first_careunit IS NOT NULL
),
rr_measurements AS (
  SELECT ce.subject_id, ce.stay_id, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN icu_stays isu ON ce.subject_id = isu.subject_id 
    AND ce.stay_id = isu.stay_id
    AND ce.itemid IN (618, 619, 220210)
    AND ce.valuenum IS NOT NULL
  WHERE DATE(ce.charttime) >= DATE(isu.intime) + INTERVAL 1 DAY  -- Day 2 or later
)
SELECT MAX(valuenum) AS max_respiratory_rate
FROM rr_measurements;