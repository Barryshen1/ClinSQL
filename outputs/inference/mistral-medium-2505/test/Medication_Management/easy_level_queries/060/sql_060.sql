WITH ace_inhibitors AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    pres.pharmacy_id,
    pres.drug,
    pres.starttime,
    pres.stoptime,
    TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    pres.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND LOWER(pres.drug) IN (
      'lisinopril', 'enalapril', 'ramipril', 'benazepril',
      'captopril', 'fosinopril', 'moexipril', 'perindopril',
      'quinapril', 'trandolapril'
    )
    AND pres.stoptime IS NOT NULL
)

SELECT
  subject_id,
  drug,
  duration_days
FROM
  ace_inhibitors
ORDER BY
  duration_days DESC
LIMIT 1;