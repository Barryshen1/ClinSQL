SELECT
  STDDEV(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS los_sd_days
FROM
  `physionet-data.mimiciv_3_1_hosp`.patients pat
JOIN
  `physionet-data.mimiciv_3_1_hosp`.admissions adm
  ON pat.subject_id = adm.subject_id
JOIN
  `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
  ON adm.hadm_id = diag.hadm_id
WHERE
  pat.gender = 'M'
  -- Calculate age at admission
  AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 51 AND 61
  -- Primary diagnosis
  AND diag.seq_num = 1
  -- Hemorrhagic stroke: ICD-9 (430-432) and ICD-10 (I60-I62)
  AND (
    (diag.icd_version = 9 AND diag.icd_code >= '430' AND diag.icd_code <= '432')
    OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I60%' 
                                   OR diag.icd_code LIKE 'I61%' 
                                   OR diag.icd_code LIKE 'I62%'))
  )
  -- Ensure valid discharge time
  AND adm.dischtime IS NOT NULL
  AND adm.admittime IS NOT NULL;