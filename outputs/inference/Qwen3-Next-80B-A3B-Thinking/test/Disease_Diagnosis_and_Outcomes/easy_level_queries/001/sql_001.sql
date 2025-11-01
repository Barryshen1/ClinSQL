SELECT AVG(DATE_DIFF(adm.dischtime, adm.admittime, DAY)) AS avg_los
FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
WHERE pat.gender = 'M'
  AND pat.anchor_age BETWEEN 86 AND 96
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
      ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
    WHERE diag.hadm_id = adm.hadm_id
      AND (
        d_diag.long_title LIKE '%upper gastrointestinal bleed%'
        OR d_diag.long_title LIKE '%gastrointestinal hemorrhage%'
        OR d_diag.long_title LIKE '%UGIB%'
        OR d_diag.long_title LIKE '%upper GI bleed%'
      )
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
      ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
    WHERE diag.hadm_id = adm.hadm_id
      AND (
        d_diag.long_title LIKE '%exacerbation of COPD%'
        OR d_diag.long_title LIKE '%COPD exacerbation%'
        OR d_diag.long_title LIKE '%chronic obstructive pulmonary disease exacerbation%'
      )
  );