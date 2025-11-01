WITH 
-- Filter patients aged 76-86 who are male
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 76 AND 86
),

-- Get ICU stays in step-down/IMC care units
icu_stays AS (
  SELECT i.stay_id, i.subject_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_patients p ON i.subject_id = p.subject_id
  WHERE i.first_careunit IN ('Step-Down', 'IMC') OR i.last_careunit IN ('Step-Down', 'IMC')
),

-- Get SBP measurements within the first 24 hours of ICU stay
sbp_measurements AS (
  SELECT i.stay_id, c.valuenum
  FROM icu_stays i
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c ON i.stay_id = c.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d ON c.itemid = d.itemid
  WHERE c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
  AND d.label = 'Systolic Blood Pressure'
)

-- Calculate the SD of SBP for the cohort
SELECT STDDEV(valuenum) AS sd_sbp
FROM sbp_measurements;