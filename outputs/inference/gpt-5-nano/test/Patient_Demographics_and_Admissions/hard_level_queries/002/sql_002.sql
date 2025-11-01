WITH study_bounds AS (
  SELECT
    MIN(admittime) AS min_adm,
    MAX(admittime) AS max_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE di.seq_num = 1
    AND d.long_title LIKE '%Pneumonia%'
    AND a.admittime BETWEEN (SELECT min_adm FROM study_bounds) AND (SELECT max_adm FROM study_bounds)
    AND a.admission_type = 'EMERGENCY'
    AND p.gender = 'Male'
    AND p.anchor_age BETWEEN 77 AND 87
)
SELECT COUNT(*) AS index_admissions
FROM eligible_admissions
WHERE rn = 1;