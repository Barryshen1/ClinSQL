WITH patient_info AS (
  SELECT p.subject_id, p.anchor_age, pi.stay_id, pi.intime, pi.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` pi ON p.subject_id = pi.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 41 AND 51
),
rr_data AS (
  SELECT pi.stay_id, AVG(ce.valuenum) AS avg_rr
  FROM patient_info pi
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON pi.stay_id = ce.stay_id
  WHERE ce.itemid = 220210 AND ce.charttime BETWEEN pi.intime AND TIMESTAMP_ADD(pi.intime, INTERVAL 48 HOUR)
  GROUP BY pi.stay_id
),
rr_categories AS (
  SELECT stay_id,
         CASE
           WHEN avg_rr < 12 THEN '<12'
           WHEN avg_rr BETWEEN 12 AND 20 THEN '12-20'
           WHEN avg_rr BETWEEN 21 AND 29 THEN '21-29'
           ELSE '>=30'
         END AS rr_category
  FROM rr_data
),
stroke_patients AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%stroke%' AND di.icd_version = 10
),
stroke_and_rr AS (
  SELECT rc.rr_category, COUNT(DISTINCT pi.stay_id) AS total_patients, COUNT(DISTINCT sp.hadm_id) AS stroke_count
  FROM patient_info pi
  JOIN rr_categories rc ON pi.stay_id = rc.stay_id
  LEFT JOIN stroke_patients sp ON pi.hadm_id = sp.hadm_id
  GROUP BY rc.rr_category
)
SELECT rr_category, total_patients, stroke_count, SAFE_DIVIDE(stroke_count, total_patients) * 100 AS stroke_rate
FROM stroke_and_rr;