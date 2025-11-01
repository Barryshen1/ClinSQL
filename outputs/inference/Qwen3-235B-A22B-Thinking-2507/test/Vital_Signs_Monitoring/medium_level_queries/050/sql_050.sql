WITH cohort AS (
  SELECT 
    icustays.stay_id,
    icustays.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` admissions
    ON icustays.hadm_id = admissions.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON admissions.subject_id = patients.subject_id
  WHERE 
    patients.gender = 'F'
    AND (
      patients.anchor_age + 
      (EXTRACT(YEAR FROM admissions.admittime) - patients.anchor_year)
    ) BETWEEN 67 AND 77
),
hr_measurements AS (
  SELECT 
    c.stay_id,
    chartevents.valuenum AS hr
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
    ON c.stay_id = chartevents.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` d_items
    ON chartevents.itemid = d_items.itemid
  WHERE 
    d_items.label IN ('Heart Rate', 'Heart Rate (Monitored)')
    AND chartevents.valuenum IS NOT NULL
    AND chartevents.charttime >= c.intime
    AND chartevents.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
),
stay_avg_hr AS (
  SELECT 
    stay_id,
    AVG(hr) AS avg_hr
  FROM hr_measurements
  GROUP BY stay_id
)
SELECT 
  (COUNTIF(avg_hr <= 110) * 100.0) / COUNT(*) AS percentile
FROM stay_avg_hr;