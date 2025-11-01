SELECT MAX(DATETIME_DIFF(a.dischtime, a.admittime, DAY)) AS max_los_days
FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
  ON a.subject_id = p.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  ON a.hadm_id = di.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
  ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
WHERE p.gender = 'F'
  AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
  AND di.seq_num = 1
  AND di.icd_version = 10
  AND (
    d.icd_code LIKE 'A41%'  -- Sepsis
    OR d.icd_code LIKE 'R652%'  -- Septic shock / severe sepsis
  )
  AND a.dischtime IS NOT NULL;