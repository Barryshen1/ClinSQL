SELECT MAX(DATE_DIFF(stoptime, starttime, DAY)) AS longest_prescription_duration_days
FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON p.subject_id = pat.subject_id
WHERE pat.gender = 'F'
  AND pat.anchor_age BETWEEN 38 AND 48
  AND LOWER(p.drug) IN (
    'lisinopril', 'enalapril', 'ramipril', 'captopril', 'benazepril',
    'quinapril', 'fosinopril', 'moexipril', 'perindopril', 'trandolapril'
  )
  AND p.stoptime IS NOT NULL
  AND p.stoptime >= p.starttime;