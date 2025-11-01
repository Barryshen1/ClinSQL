SELECT MAX(DATETIME_DIFF(pr.stoptime, pr.starttime, DAY)) AS max_dapt_duration_days
FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
  ON pr.hadm_id = adm.hadm_id
JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON adm.subject_id = pat.subject_id
WHERE pat.gender = 'M'
  AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 84 AND 94
  AND LOWER(pr.drug) IN ('aspirin', 'clopidogrel', 'ticagrelor', 'prasugrel')
  AND pr.starttime IS NOT NULL
  AND pr.stoptime IS NOT NULL
  AND pr.stoptime >= pr.starttime;