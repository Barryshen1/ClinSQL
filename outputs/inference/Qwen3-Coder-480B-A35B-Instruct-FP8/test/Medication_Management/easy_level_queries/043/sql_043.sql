SELECT
  MIN(DATETIME_DIFF(adm.dischtime, adm.admittime, DAY)) AS shortest_inpatient_duration_days
FROM
  physionet-data.mimiciv_3_1_hosp.admissions AS adm
JOIN
  physionet-data.mimiciv_3_1_hosp.patients AS pat
  ON adm.subject_id = pat.subject_id
JOIN
  physionet-data.mimiciv_3_1_hosp.prescriptions AS rx
  ON adm.hadm_id = rx.hadm_id
WHERE
  pat.gender = 'F'
  AND pat.anchor_age BETWEEN 81 AND 91
  AND LOWER(rx.drug) IN ('hydralazine', 'isosorbide dinitrate');