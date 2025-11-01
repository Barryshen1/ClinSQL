WITH female_51_61 AS (
  SELECT p.subject_id, p.anchor_age, i.stay_id, i.intime, i.outtime
  FROM physionet-data.mimiciv_3_1_icu.icustays i
  JOIN physionet-data.mimiciv_3_1_hosp.patients p ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),

mech_vent AS (
  SELECT DISTINCT subject_id, stay_id
  FROM physionet-data.mimiciv_3_1_icu.procedureevents
  WHERE itemid = 720 -- Invasive Mechanical Ventilation
),

vitals_48h AS (
  SELECT 
    c.stay_id,
    MAX(CASE WHEN di.label = 'Heart Rate' AND c.valuenum < 50 THEN 1
             WHEN di.label = 'Heart Rate' AND c.valuenum > 130 THEN 1
             ELSE 0 END) AS abnormal_hr,
    MAX(CASE WHEN di.label = 'Arterial BP Systolic' AND c.valuenum < 90 THEN 1
             WHEN di.label = 'Arterial BP Systolic' AND c.valuenum > 180 THEN 1
             ELSE 0 END) AS abnormal_sbp,
    MAX(CASE WHEN di.label = 'Respiratory Rate' AND c.valuenum < 10 THEN 1
             WHEN di.label = 'Respiratory Rate' AND c.valuenum > 30 THEN 1
             ELSE 0 END) AS abnormal_rr,
    MAX(CASE WHEN di.label = 'SpO2' AND c.valuenum < 90 THEN 1
             ELSE 0 END) AS abnormal_spo2,
    MAX(CASE WHEN di.label = 'GCS Total' AND c.valuenum < 15 THEN 1
             ELSE 0 END) AS low_gcs
  FROM physionet-data.mimiciv_3_1_icu.chartevents c
  JOIN physionet-data.mimiciv_3_1_icu.d_items di ON c.itemid = di.itemid
  WHERE c.charttime >= TIMESTAMP_SUB(c.stay_id.intime, INTERVAL 48 HOUR)
    AND c.charttime <= c.stay_id.intime + INTERVAL 4;