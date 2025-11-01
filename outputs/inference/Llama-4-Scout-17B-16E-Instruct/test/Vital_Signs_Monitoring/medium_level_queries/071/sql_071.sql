WITH 
  -- Filter patients by age and gender
  filtered_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 38 AND 48
  ),
  
  -- Select relevant ICU stays
  icu_stays AS (
    SELECT stay_id, subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
    WHERE subject_id IN (SELECT subject_id FROM filtered_patients)
  ),
  
  -- Extract SpO2 measurements
  spo2_measurements AS (
    SELECT stay_id, valueuom, valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents`
    WHERE itemid = 220050  -- SpO2
      AND stay_id IN (SELECT stay_id FROM icu_stays)
      AND valuenum IS NOT NULL
  ),
  
  -- Calculate mean SpO2 per stay
  mean_spo2_per_stay AS (
    SELECT stay_id, AVG(valuenum) AS mean_spo2
    FROM spo2_measurements
    GROUP BY stay_id
  )

-- Calculate proportion of stays with mean SpO2 ≤ 92%
SELECT 
  COUNTIF(mean_spo2 <= 92) / COUNT(stay_id) AS proportion
FROM mean_spo2_per_stay;