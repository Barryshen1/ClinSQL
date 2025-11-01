WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hadm_id,
    a.admission_type,
    a.admission_location,
    d.long_title AS primary_diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 51 AND 61
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'ED'
    AND d.icd_code LIKE 'K85%' -- Acute pancreatitis ICD-10 codes
), Readmission AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.dischtime AS index_dischtime,
    a2.admittime AS readmit_admittime,
    a2.hadm_id AS readmit_hadm_id
  FROM PatientCohort AS pc
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
    ON pc.subject_id = a2.subject_id
  WHERE
    a2.admittime > pc.dischtime
    AND a2.admittime <= DATETIME_ADD(pc.dischtime, INTERVAL 30 DAY)
), ReadmissionStatus AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    CASE WHEN r.readmit_hadm_id IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30_day
  FROM PatientCohort AS pc
  LEFT JOIN Readmission AS r
    ON pc.subject_id = r.subject_id
), IndexLOS AS (
  SELECT
    subject_id,
    hadm_id,
    readmitted_30_day,
    DATETIME_DIFF(dischtime, admittime, DAY) AS index_los
  FROM PatientCohort
), ReadmissionLOS AS (
  SELECT
    r.subject_id,
    r.readmit_hadm_id,
    r.readmit_admittime,
    DATETIME_DIFF(a2.dischtime, a2.admittime, DAY) AS readmit_los
  FROM Readmission AS r
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
    ON r.readmit_hadm_id = a2.hadm_id
), CombinedStats AS (
  SELECT
    rs.subject_id,
    rs.hadm_id,
    rs.readmitted_30_day,
    il.index_los,
    rl.readmit_los
  FROM ReadmissionStatus AS rs
  LEFT JOIN IndexLOS AS il
    ON rs.subject_id = il.subject_id AND rs.hadm_id = il.hadm_id
  LEFT JOIN ReadmissionLOS AS rl
    ON rs.subject_id = rl.subject_id AND rs.hadm_id = rl.readmit_hadm_id
), FinalStats AS (
  SELECT
    readmitted_30_day,
    AVG(index_los) AS avg_index_los,
    AVG(readmit_los) AS avg_readmit_los,
    COUNTIF(index_los > 9) / COUNT(subject_id) AS pct_los_gt_9_days
  FROM CombinedStats
  GROUP BY
    readmitted_30_day
)
SELECT
  readmitted_30_day,
  avg_index_los,
  avg_readmit_los,
  pct;