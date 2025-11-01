SELECT APPROX_QUANTILES(DATE_DIFF(stoptime, starttime, DAY), 4)[OFFSET(1)] AS p25_duration_days
FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON p.subject_id = pat.subject_id
WHERE pat.gender = 'F'
  AND pat.anchor_age = 55
  AND LOWER(p.drug) IN (
    'lisinopril', 'enalapril', 'ramipril', 'captopril', 'benazepril',
    'quinapril', 'fosinopril', 'moexipril', 'perindopril', 'trandolapril'
  )
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL;