SELECT 
  AVG(DATETIME_DIFF(pres.stoptime, pres.starttime, DAY)) AS avg_warfarin_duration_days
FROM 
  `physionet-data.mimiciv_3_1_hosp`.patients pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm 
    ON pat.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pres 
    ON adm.hadm_id = pres.hadm_id
WHERE 
  LOWER(pres.drug) LIKE '%warfarin%'
  AND pat.gender = 'M'
  AND pres.stoptime IS NOT NULL
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 43 AND 53;