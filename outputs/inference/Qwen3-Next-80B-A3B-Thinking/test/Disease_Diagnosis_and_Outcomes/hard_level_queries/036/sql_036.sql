WITH pneumonia_patients AS (
  SELECT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%pneumonia%'
),
patients_with_pneumonia AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN pneumonia_patients pp
    ON a.hadm_id = pp.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 73 AND 83
),
diagnosis_counts AS (
  SELECT p.subject_id, p.hadm_id, COUNT(*) AS diagnosis_count
  FROM patients_with_pneumonia p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON p.subject_id = d.subject_id AND p.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title NOT LIKE '%pneumonia%'
  GROUP BY p.subject_id, p.hadm_id
),
percentile AS (
  SELECT PERCENTILE_CONT(diagnosis_count, 0.75) WITHIN GROUP (ORDER BY diagnosis_count) AS top_quartile_threshold
  FROM diagnosis_counts
),
top_quartile_patients AS (
  SELECT dc.subject_id, dc.hadm_id, dc.diagnosis_count, p.admittime, p.dischtime, p.hospital_expire_flag
  FROM diagnosis_counts dc
  JOIN patients_with_pneumonia p
    ON dc.subject_id = p.subject_id AND dc.hadm_id = p.hadm_id
  CROSS JOIN percentile
  WHERE dc.diagnosis_count >= percentile.top_quartile_threshold
),
sepsis_patients AS (
  SELECT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE di.long_title LIKE '%sepsis%'
),
metrics AS (
  SELECT
    SUM(CASE WHEN t.hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS mortality_percent,
    SUM(CASE WHEN s.subject_id IS NOT NULL THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS complication_percent,
    PERCENTILE_CONT(TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY), 0.5) WITHIN GROUP (ORDER BY TIMESTAMP_DIFF(t.dischtime, t.admittime, DAY)) AS median_survival_days
  FROM top_quartile_patients t
  LEFT JOIN sepsis_patients s
    ON t.subject_id = s.subject_id AND t.hadm_id = s.hadm_id
)
SELECT mortality_percent, complication_percent, median_survival_days
FROM metrics;