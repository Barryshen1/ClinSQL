SELECT COUNT(*) AS num_admissions
FROM physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS diag
  ON adm.hadm_id = diag.hadm_id
WHERE
  pat.gender = 'M'
  AND pat.anchor_age BETWEEN 43 AND 53
  AND adm.insurance LIKE '%Medicare%'
  AND adm.admission_location LIKE '%Emergency%'
  AND diag.seq_num = 1
  AND (
    -- ICD-9 DKA codes
    (diag.icd_version = 9 AND diag.icd_code IN ('25010', '25011', '25012', '25013'))
    OR
    -- ICD-10 DKA codes
    (diag.icd_version = 10 AND diag.icd_code IN (
      'E10.10', 'E10.11', 'E10.12', 'E10.13', 'E10.14', 'E10.15', 'E10.16', 'E10.19',
      'E11.10', 'E11.11', 'E11.12', 'E11.13', 'E11.14', 'E11.15', 'E11.16', 'E11.19',
      'E13.10', 'E13.11', 'E13.12', 'E13.13', 'E13.14', 'E13.15', 'E13.16', 'E13.19'
    ))
  );