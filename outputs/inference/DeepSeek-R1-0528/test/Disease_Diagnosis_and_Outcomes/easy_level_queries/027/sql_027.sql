SELECT MAX(los_days) AS max_los_days
FROM (
  SELECT
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
    AND adm.subject_id = diag.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON diag.icd_code = d.icd_code
    AND diag.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND diag.seq_num = 1  -- Primary diagnosis
    AND adm.dischtime > adm.admittime  -- Valid LOS
    AND (d.long_title LIKE '%upper%gastrointestinal%bleed%'
      OR d.long_title LIKE '%upper%gastrointestinal%hemorrhage%'
      OR d.long_title LIKE '%hematemesis%'
      OR d.long_title LIKE '%melena%')
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) 
        BETWEEN 49 AND 59)  -- Fixed: Added closing parenthesis
);