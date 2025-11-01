SELECT COUNT(DISTINCT a.hadm_id) AS index_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
  ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  ON di.subject_id = a.subject_id
  AND di.hadm_id = a.hadm_id
WHERE
  -- Age at admission between 62 and 72
  (CAST(p.anchor_age AS INT64) +
   (EXTRACT(YEAR FROM a.admittime) - CAST(p.anchor_year AS INT64))
  ) BETWEEN 62 AND 72
  -- Female
  AND UPPER(p.gender) = 'F'
  -- Medicare
  AND UPPER(a.insurance) = 'MEDICARE'
  -- Admitted from the emergency department
  AND UPPER(a.admission_type) = 'EMERGENCY'
  -- Principal diagnosis (seq_num = 1)
  AND di.seq_num = 1
  -- Syncope codes: ICD-9 780.2 or ICD-10 R55
  AND (
        (di.icd_version = 9 AND di.icd_code = '780.2')
     OR (di.icd_version = 10 AND di.icd_code = 'R55')
      );