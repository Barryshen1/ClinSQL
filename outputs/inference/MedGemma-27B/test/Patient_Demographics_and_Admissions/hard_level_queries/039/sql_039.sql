WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    d.long_title AS principal_diagnosis,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 65 AND 75
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'ED'
    AND d.icd_code IN ('J96.00', 'J96.01', 'J96.02', 'J96.10', 'J96.11', 'J96.12', 'J96.2', 'J96.3', 'J96.9') -- Acute respiratory failure codes (ICD-10)
), Readmission AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.dischtime AS index_dischtime,
    MIN(a2.admittime) AS readmit_time
  FROM PatientCohort AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
    ON pc.subject_id = a2.subject_id
  WHERE
    a2.admittime > pc.dischtime
    AND a2.admittime <= DATETIME_ADD(pc.dischtime, INTERVAL 30 DAY)
  GROUP BY
    pc.subject_id,
    pc.hadm_id,
    pc.dischtime
), ReadmissionStatus AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    CASE WHEN r.readmit_time IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM PatientCohort AS pc
  LEFT JOIN Readmission AS r
    ON pc.subject_id = r.subject_id AND pc.hadm_id = r.hadm_id
), IndexLOS AS (
  SELECT
    subject_id,
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, DAY) AS index_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
), ReadmissionLOS AS (
  SELECT
    r.subject_id,
    r.hadm_id,
    DATETIME_DIFF(a2.dischtime, a2.admittime, DAY) AS readmit_los
  FROM Readmission AS r
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
    ON r.subject_id = a2.subject_id AND r.readmit_time = a2.admittime
)
SELECT
  AVG(CASE WHEN rs.readmitted_30d = 1 THEN 1 ELSE 0 END) AS readmission_rate,
  MEDIAN(CASE WHEN rs.readmitted_30d = 1 THEN il.index_los ELSE NULL END) AS median_index_los_readmitted,
  MEDIAN(CASE WHEN rs.readmitted_30d = 0 THEN il.index_los ELSE NULL END) AS median_index_los_non_readmitted,
  AVG(CASE WHEN il.index_los > 9 THEN 1 ELSE 0 END) AS percent_los_greater_than_9_days
FROM ReadmissionStatus AS rs
JOIN IndexLOS AS il
  ON rs.subject_id = il.subject_id AND rs.hadm_id = il.hadm_id;