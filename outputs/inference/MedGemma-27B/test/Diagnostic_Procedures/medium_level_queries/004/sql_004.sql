WITH HF_Admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    d.long_title AS diagnosis_title,
    d.icd_version,
    di.seq_num AS diagnosis_seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di ON a.hadm_id = di.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND d.long_title LIKE '%heart failure%'
    AND di.seq_num = 1 -- Primary diagnosis
),
HF_Admissions_Secondary AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    a.discharge_location,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    d.long_title AS diagnosis_title,
    d.icd_version,
    di.seq_num AS diagnosis_seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p ON a.subject_id = p.subject_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di ON a.hadm_id = di.hadm_id
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND d.long_title LIKE '%heart failure%'
    AND di.seq_num > 1 -- Secondary diagnosis
),
Imaging_Events AS (
  SELECT
    h.hadm_id,
    hcp.hcpcs_cd,
    hcp.short_description,
    COUNT(hcp.hcpcs_cd) AS imaging_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS h
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS hcp ON h.hadm_id = hcp.hadm_id
  WHERE
    hcp.hcpcs_cd IN ('7700211', '7700229', '7700334', '77059', '77061', '77062', '77063', '77067', '77068', '77069', '77071', '77072', '77073') -- CT/MRI codes
  GROUP BY
    h.hadm_id, hcp.hcpcs_cd, hcp.short_description
),
LOS_Calculation AS (
  SELECT
    hadm_id,
    (TIMESTAMP_DIFF(dischtime, admittime;