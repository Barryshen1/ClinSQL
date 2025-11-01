SELECT COUNT(DISTINCT a.hadm_id)
FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
WHERE p.gender = 'F'
  AND a.admission_location = 'EMERGENCY ROOM'
  AND p.anchor_age BETWEEN 68 AND 78
  AND a.dischtime IS NOT NULL
  AND a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE ((icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%')  -- ICD-9
        OR (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))  -- ICD-10
      AND icd_version IN (9, 10)
      AND seq_num = 1
  );