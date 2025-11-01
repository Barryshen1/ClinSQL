SELECT COUNT(*) AS completed_admissions_count
FROM `physionet-data.mimiciv_3_1_hosp`.patients p
JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON p.subject_id = a.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON a.hadm_id = di.hadm_id AND p.subject_id = di.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
WHERE p.gender = 'F'
  AND a.insurance = 'Medicare'
  AND LOWER(a.admission_location) LIKE '%emergency%'
  AND a.dischtime IS NOT NULL
  AND di.seq_num = 1
  AND LOWER(d.long_title) LIKE '%bowel obstruction%'
     OR LOWER(d.long_title) LIKE '%intestinal obstruction%'
  AND (
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
  ) BETWEEN 43 AND 53;