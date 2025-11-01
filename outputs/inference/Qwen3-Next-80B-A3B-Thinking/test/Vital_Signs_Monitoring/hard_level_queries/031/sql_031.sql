WITH patients_icu AS (
  SELECT
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.los,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    a.admittime,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 63 AND 73
),
post_op_patients AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    p.los,
    p.hospital_expire_flag
  FROM patients_icu p
  JOIN `physionet-data.mimiciv_3_1_hosp.services` s ON p.hadm_id = s.hadm_id
  WHERE s.curr_service = 'SURG'
),
qsofa_score AS (
  SELECT
    p.subject_id,
    p.stay_id,
    MAX(CASE WHEN ce.itemid = 220210 AND ce.valuenum >= 22 THEN 1 ELSE 0 END) AS rr_ge22,
    MAX(CASE WHEN ce.itemid = 220050 AND ce.valuenum <= 100 THEN 1 ELSE 0 END) AS sbp_le100,
    MAX(CASE WHEN ce.itemid = 223900 AND ce.valuenum < 15 THEN 1 ELSE 0 END) AS gcs_lt15,
    (MAX(CASE WHEN ce.itemid = 220210 AND ce.valuenum >= 22 THEN 1 ELSE 0 END) +
     MAX(CASE WHEN ce.itemid = 220050 AND ce.valuenum <= 100 THEN 1 ELSE 0 END) +
     MAX(CASE WHEN ce.itemid = 223900 AND ce.valuenum < 15 THEN 1 ELSE 0 END)) AS qsofa_score
  FROM post_op_patients p
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON p.stay_id = ce.stay_id
  WHERE ce.itemid IN (220210, 220050, 223900)
  GROUP BY p.subject_id, p.stay_id
),
qsofa_quartiles AS (
  SELECT
    subject_id,
    stay_id,
    qsofa_score,
    NTILE(4) OVER (ORDER BY qsofa_score DESC) AS quartile
  FROM qsofa_score
),
top_quartile_95th AS (
  SELECT
    PERCENTILE_CONT(qsofa_score, 0.95) WITHIN GROUP (ORDER BY qsofa_score) AS qsofa_95th_percentile
  FROM qsofa_quartiles
  WHERE quartile = 1
),
patient_metrics AS (
  SELECT
    q.subject_id,
    q.quartile,
    MAX(CASE WHEN ce.itemid = 223761 AND ce.valuenum > 38.5 THEN 1 ELSE 0 END) AS has_fever,
    MAX(CASE WHEN ce.itemid = 220277 AND ce.valuenum < 90 THEN 1 ELSE 0 END) AS has_spO2_lt90,
    COUNT(CASE WHEN ce.itemid = 220210 AND ce.valuenum > 20 THEN 1 END) AS rr_gt20_count,
    p.los,
    p.hospital_expire_flag
  FROM qsofa_quartiles q
  JOIN post_op_patients p ON q.subject_id = p.subject_id AND q.stay_id = p.stay_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce ON p.stay_id = ce.stay_id
  GROUP BY q.subject_id, q.quartile, p.los, p.hospital_expire_flag
)
SELECT
  (SELECT qsofa_95th_percentile FROM top_quartile_95th) AS instability_95th_percentile,
  AVG(CASE WHEN quartile = 1 THEN has_fever END) AS top_quartile_fever_rate,
  AVG(CASE WHEN quartile != 1 THEN has_fever END) AS other_fever_rate,
  AVG(CASE WHEN quartile = 1 THEN has_spO2_lt90 END) AS top_quartile_spO2_lt90,
  AVG(CASE WHEN quartile != 1 THEN has_spO2_lt90 END) AS other_spO2_lt90,
  AVG(CASE WHEN quartile = 1 THEN rr_gt20_count END) AS top_quartile_rr_gt20,
  AVG(CASE WHEN quartile != 1 THEN rr_gt20_count END) AS other_rr_gt20,
  AVG(CASE WHEN quartile = 1 THEN los END) AS top_quartile_los,
  AVG(CASE WHEN quartile != 1 THEN los END) AS other_los,
  AVG(CASE WHEN quartile = 1 THEN hospital_expire_flag END) AS top_quartile_mortality,
  AVG(CASE WHEN quartile != 1 THEN hospital_expire_flag END) AS other_mortality
FROM patient_metrics;