SELECT 
  MIN(DATETIME_DIFF(pres.stoptime, pres.starttime, DAY)) AS min_duration_days
FROM 
  `physionet-data.mimiciv_3_1_hosp`.patients pat
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp`.admissions adm
  ON pat.subject_id = adm.subject_id
INNER JOIN 
  `physionet-data.mimiciv_3_1_hosp`.prescriptions pres
  ON adm.hadm_id = pres.hadm_id
WHERE 
  pat.gender = 'F'
  AND LOWER(pres.drug) LIKE '%atorvastatin%'
  AND SAFE_CAST(pres.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
  AND LOWER(pres.dose_unit_rx) = 'mg'
  AND pres.starttime IS NOT NULL
  AND pres.stoptime IS NOT NULL
  AND pres.stoptime >= pres.starttime
  AND (
    pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)
  ) BETWEEN 86 AND 96;