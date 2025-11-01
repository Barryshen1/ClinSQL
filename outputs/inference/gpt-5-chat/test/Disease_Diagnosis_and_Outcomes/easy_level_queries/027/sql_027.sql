SELECT
  MAX(DATE_DIFF(a.dischtime, a.admittime, DAY)) AS max_los_days
FROM physionet-data.mimiciv_3_1_hosp.patients p
JOIN physionet-data.mimiciv_3_1_hosp.admissions a
  ON p.subject_id = a.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  ON a.subject_id = d.subject_id
  AND a.hadm_id = d.hadm_id
JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses di
  ON d.icd_code = di.icd_code
  AND d.icd_version = di.icd_version
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 49 AND 59
  AND d.seq_num = 1
  AND (
    LOWER(di.long_title) LIKE '%upper gastrointestinal%'
    OR LOWER(di.long_title) LIKE '%gastrointestinal hemorrhage%'
    OR LOWER(di.long_title) LIKE '%esophageal hemorrhage%'
    OR LOWER(di.long_title) LIKE '%gastric hemorrhage%'
    OR LOWER(di.long_title) LIKE '%duodenal hemorrhage%'
    OR LOWER(di.long_title) LIKE '%ugib%'
  )
  AND a.admittime IS NOT NULL
  AND a.dischtime IS NOT NULL;