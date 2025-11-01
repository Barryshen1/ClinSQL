WITH patient_cohort AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 64 AND 74
),
aspirin_rx AS (
  SELECT hadm_id, starttime, stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%aspirin%' AND stoptime IS NOT NULL
),
p2y12_rx AS (
  SELECT hadm_id, starttime, stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE (LOWER(drug) LIKE '%clopidogrel%' OR LOWER(drug) LIKE '%prasugrel%' OR LOWER(drug) LIKE '%ticagrelor%') AND stoptime IS NOT NULL
),
dual_antiplatelet AS (
  SELECT a.hadm_id
  FROM aspirin_rx a
  INNER JOIN p2y12_rx p ON a.hadm_id = p.hadm_id
  WHERE a.starttime <= p.stoptime AND p.starttime <= a.stoptime
),
prescription_durations AS (
  SELECT pc.hadm_id,
         DATE_DIFF(MIN(a.stoptime), MAX(a.starttime), DAY) AS rx_duration
  FROM dual_antiplatelet da
  INNER JOIN patient_cohort pc ON da.hadm_id = pc.hadm_id
  INNER JOIN (
    SELECT hadm_id, starttime, stoptime FROM aspirin_rx
    UNION ALL
    SELECT hadm_id, starttime, stoptime FROM p2y12_rx
  ) a ON pc.hadm_id = a.hadm_id
  GROUP BY pc.hadm_id
)
SELECT APPROX_QUANTILES(rx_duration, 100)[OFFSET(50)] AS median_rx_duration
FROM prescription_durations;