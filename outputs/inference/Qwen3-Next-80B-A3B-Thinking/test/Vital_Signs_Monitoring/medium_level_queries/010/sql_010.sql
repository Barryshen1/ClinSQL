WITH averages AS (
  SELECT 
    icustays.stay_id,
    AVG(chartevents.valuenum) AS avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icustays
    ON chartevents.stay_id = icustays.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` admissions
    ON icustays.hadm_id = admissions.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON admissions.subject_id = patients.subject_id
  WHERE 
    patients.gender = 'F'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)) BETWEEN 77 AND 87
    AND chartevents.itemid IN (220050, 220179)
    AND chartevents.charttime BETWEEN icustays.intime AND TIMESTAMP_ADD(icustays.intime, INTERVAL 48 HOUR)
    AND chartevents.valuenum IS NOT NULL
  GROUP BY icustays.stay_id
)
SELECT 
  (COUNTIF(avg_sbp <= 160) * 100.0 / COUNT(*)) AS percentile
FROM averages;