SELECT MAX(DATETIME_DIFF(pres.stoptime, pres.starttime, DAY)) AS max_duration_days
FROM `physionet-data.mimiciv_3_1_hosp`.patients pat
JOIN `physionet-data.mimiciv_3_1_hosp`.admissions adm
  ON pat.subject_id = adm.subject_id
JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pres
  ON adm.hadm_id = pres.hadm_id
WHERE LOWER(pres.drug) = 'digoxin'
  AND pat.gender = 'M'
  AND pres.starttime IS NOT NULL
  AND pres.stoptime IS NOT NULL
  AND pres.starttime >= adm.admittime
  AND pres.stoptime <= COALESCE(adm.dischtime, pres.stoptime)
  AND (EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age)) BETWEEN 82 AND 92;