SELECT MAX(icu.los) AS max_icu_los
FROM `physionet-data.mimiciv_3_1_hosp`.patients p
INNER JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd proc
  ON p.subject_id = proc.subject_id
INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
  ON p.subject_id = icu.subject_id AND proc.hadm_id = icu.hadm_id
WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 59 AND 69
  AND proc.icd_version = 10
  AND proc.icd_code LIKE '021%';