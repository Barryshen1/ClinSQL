WITH IndexAdmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.admission_location,
    a.discharge_location,
    a.insurance,
    a.language,
    a.marital_status,
    a.race,
    a.edregtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_year_group,
    p.dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'Emergency Department'
    AND a.hospital_expire_flag = 0
    AND a.deathtime IS NULL
),
CellulitisAdmissions AS (
  SELECT
    ia.subject_id,
    ia.hadm_id,
    ia.admittime,
    ia.dischtime,
    ia.deathtime,
    ia.admission_type,
    ia.admission_location,
    ia.discharge_location,
    ia.insurance,
    ia.language,
    ia.marital_status,
    ia.race,
    ia.edregtime,
    ia.hospital_expire_flag,
    ia.gender,
    ia.anchor_age,
    ia.anchor_year,
    ia.anchor_year_group,
    ia.dod
  FROM
    IndexAdmissions AS ia
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON ia.subject_id = di.subject_id
    AND ia.hadm_id = di.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS ddi
    ON di.icd_code = ddi.icd_code
    AND di.icd_version = ddi.icd_version
  WHERE
    ddi.long_title LIKE '%cellulitis%'
    AND di.seq_num = 1
),
Readmissions AS (
  SELECT
    ca.subject_id,
    ca.hadm_id AS index_hadm_id,
    ca.admittime AS index_admittime,
    ca.dischtime AS index_dischtime,
    ra.hadm_id AS readmission_hadm_id,
    ra.admittime AS readmission_admittime,
    ra.dischtime AS readmission_dischtime
  FROM
    CellulitisAdmissions AS ca
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS ra
  ON ca.subject_id = ra.subject_id
  AND ra.admittime > ca.dischtime
  AND ra.admittime <= TIMESTAMP_ADD(ca.dischtime, INTERVAL 30 DAY)
)
SELECT
  COUNT(DISTINCT ca.subject_id) AS num_readmitted,
  AVG(TIMESTAMP_DIFF(ra.admittime, ca.dischtime, DAY)) AS median_los_readmitted,
  COUNT(DISTINCT ca.subject_id) / COUNT(DISTINCT ca.subject_id) AS percent_index_stays_gt_7_days
FROM
  CellulitisAdmissions AS ca
LEFT JOIN
  Readmissions AS ra
  ON ca.subject_id = ra.subject_id
  AND ca.hadm_id = ra.index_hadm_id;