SELECT 
  COUNT(DISTINCT adm.hadm_id) AS num_admissions
FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  ON adm.subject_id = pat.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  ON adm.hadm_id = diag.hadm_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 79 AND 89
  AND UPPER(adm.insurance) = 'MEDICARE'
  AND UPPER(adm.admission_location) LIKE '%EMERGENCY%'
  AND diag.seq_num = 1
  AND (
        (diag.icd_version = 9 AND (
            diag.icd_code LIKE '480%' OR
            diag.icd_code LIKE '481%' OR
            diag.icd_code LIKE '482%' OR
            diag.icd_code LIKE '483%' OR
            diag.icd_code LIKE '484%' OR
            diag.icd_code LIKE '485%' OR
            diag.icd_code LIKE '486%' OR
            diag.icd_code = '4870'
        ))
        OR
        (diag.icd_version = 10 AND (
            diag.icd_code LIKE 'J12%' OR
            diag.icd_code LIKE 'J13%' OR
            diag.icd_code LIKE 'J14%' OR
            diag.icd_code LIKE 'J15%' OR
            diag.icd_code LIKE 'J16%' OR
            diag.icd_code LIKE 'J17%' OR
            diag.icd_code LIKE 'J18%'
        ))
      )
;