WITH 
-- Identify female patients aged 81-91
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 81 AND 91
),

-- Find ICU stays for these patients
icu_stays AS (
  SELECT i.stay_id, i.subject_id, i.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN female_patients p ON i.subject_id = p.subject_id
),

-- Identify patients who received HFNC
hfnc_patients AS (
  SELECT DISTINCT ce.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label LIKE '%High flow nasal cannula%' AND ce.stay_id IN (SELECT stay_id FROM icu_stays)
),

-- Extract SBP readings for HFNC patients
sbp_readings AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS sbp
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN 
    `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE 
    di.itemid = 220179 AND -- Assuming 220179 is the itemid for SBP
    ce.stay_id IN (SELECT stay_id FROM hfnc_patients)
)

-- Calculate mean SBP per stay and find minimum
SELECT 
  MIN(mean_sbp) AS min_mean_sbp
FROM (
  SELECT 
    stay_id,
    AVG(sbp) AS mean_sbp
  FROM 
    sbp_readings
  GROUP BY 
    stay_id
);