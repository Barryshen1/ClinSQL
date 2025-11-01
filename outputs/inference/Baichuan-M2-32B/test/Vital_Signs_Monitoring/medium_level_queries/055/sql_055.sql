WITH
  spo2_items AS (
    SELECT itemid
    FROM `physionet-data.mimiciv_3_1_icu.d_items`
    WHERE label LIKE '%SpO2%'
  ),
  patient_icu AS (
    SELECT
      p.subject_id,
      p.gender,
      p.birth_date,
      i.stay_id,
      i.intime,
      i.outtime,
      DATE_DIFF(CAST(i.intime AS DATE), p.birth_date, YEAR) AS age_at_icu
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN (
      SELECT 
        subject_id, 
        gender, 
        anchor_year, 
        anchor_age,
        DATE_SUB(CAST(CONCAT(CAST(anchor_year AS STRING), '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
      FROM `physionet-data.mimiciv_3_1_hosp.patients`
    ) p
      ON i.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND DATE_DIFF(CAST(i.intime AS DATE), p.birth_date, YEAR) BETWEEN 87 AND 97
  ),
  spo2_meas AS (
    SELECT
      ce.subject_id,
      ce.hadm_id,
      ce.stay_id,
      ce.charttime,
      ce.valuenum
    FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
    INNER JOIN spo2_items si
      ON ce.itemid = si.itemid
    INNER JOIN patient_icu pi
      ON ce.subject_id = pi.subject_id
      AND ce.stay_id = pi.stay_id
    WHERE ce.charttime BETWEEN pi.intime AND TIMESTAMP_ADD(pi.intime, INTERVAL 24 HOUR)
      AND ce.valuenum IS NOT NULL
  ),
  stay_avg_spo2 AS (
    SELECT
      stay_id,
      AVG(valuenum) AS avg_spo2
    FROM spo2_meas
    GROUP BY stay_id
  ),
  all_averages AS (
    SELECT avg_spo2
    FROM stay_avg_spo2
  )
SELECT
  (COUNT(CASE WHEN avg_spo2 <= 88 THEN 1 END) * 100.0) / COUNT(*) AS percentile
FROM all_averages;