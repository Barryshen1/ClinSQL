WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.admission_location,
    a.insurance,
    d.long_title AS principal_diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON a.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON diag.icd_code = d.icd_code AND diag.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age = 82
    AND a.admission_type = 'EMERGENCY'
    AND a.admission_location = 'SNF'
    AND a.insurance = 'Medicare'
    AND diag.seq_num = 1
    AND d.long_title LIKE '%respiratory failure%'
), Readmission AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.dischtime AS index_dischtime,
    a2.admittime AS readmit_admittime,
    a2.hadm_id AS readmit_hadm_id
  FROM PatientInfo AS pi
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a2
    ON pi.subject_id = a2.subject_id
    AND a2.admittime > pi.index_dischtime
    AND a2.admittime <= DATETIME_ADD(pi.index_dischtime, INTERVAL 30 DAY)
), ReadmissionStatus AS (
  SELECT
    pi.subject_id,
    pi.hadm_id,
    pi.dischtime AS index_dischtime,
    CASE
      WHEN r.readmit_hadm_id IS NOT NULL THEN 1
      ELSE 0
    END AS readmitted_30_day
  FROM PatientInfo AS pi
  LEFT JOIN Readmission AS r
    ON pi.subject_id = r.subject_id
    AND pi.hadm_id = r.hadm_id
)
SELECT
  AVG(readmitted_30_day) AS readmission_rate,
  AVG(CASE
    WHEN readmitted_30_day = 1 THEN index_los
    ELSE NULL
  END) AS median_index_los_readmitted,
  AVG(CASE
    WHEN readmitted_30_day = 0 THEN index_los
    ELSE NULL
  END) AS median_index_los_not_readmitted,
  AVG(CASE
    WHEN index_los > 8 THEN 1
    ELSE 0
  END) AS percent_index_stays_gt_8_days
FROM (
  SELECT
    rs.subject_id,
    rs.hadm_id,
    rs.readmitted_30_day,
    TIMESTAMP_DIFF(rs.index_dischtime, a.admittime, DAY) AS index_los
  FROM ReadmissionStatus AS rs
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON rs.subject_id = a.subject_id AND rs.hadm_id = a.hadm_id
);