SELECT
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_hospital_los_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` pat
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.admissions` adm
ON
  pat.subject_id = adm.subject_id
INNER JOIN
  `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
ON
  adm.subject_id = diag.subject_id
  AND adm.hadm_id = diag.hadm_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 78 AND 88
  AND diag.seq_num = 1
  AND (
    (diag.icd_version = 'ICD-9-CM' AND (
      diag.icd_code LIKE '410%' OR
      diag.icd_code LIKE '411%' OR
      diag.icd_code LIKE '412%' OR
      diag.icd_code LIKE '413%' OR
      diag.icd_code LIKE '414%'
    ))
    OR
    (diag.icd_version = 'ICD-10-CM' AND (
      diag.icd_code LIKE 'I20%' OR
      diag.icd_code LIKE 'I21%' OR
      diag.icd_code LIKE 'I22%' OR
      diag.icd_code LIKE 'I23%' OR
      diag.icd_code LIKE 'I24%' OR
      diag.icd_code LIKE 'I25%'
    ))
  );