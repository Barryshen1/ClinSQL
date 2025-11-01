WITH pneumonia_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 77 AND 87
    AND a.insurance = 'Medicare'
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND di.seq_num = 1  -- Principal diagnosis
    AND LOWER(d.long_title) LIKE '%pneumonia%'
)

SELECT COUNT(*) AS total_index_admissions
FROM pneumonia_admissions;