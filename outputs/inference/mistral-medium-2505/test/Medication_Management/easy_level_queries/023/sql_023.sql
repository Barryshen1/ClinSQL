WITH ace_inhibitors AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    pres.hadm_id,
    pres.drug,
    pres.starttime,
    pres.stoptime,
    TIMESTAMP_DIFF(pres.stoptime, pres.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres ON a.hadm_id = pres.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 78 AND 88
    AND pres.stoptime IS NOT NULL
    AND (
      pres.drug LIKE '%lisinopril%'
      OR pres.drug LIKE '%enalapril%'
      OR pres.drug LIKE '%ramipril%'
      OR pres.drug LIKE '%benazepril%'
      OR pres.drug LIKE '%fosinopril%'
      OR pres.drug LIKE '%quinapril%'
      OR pres.drug LIKE '%perindopril%'
      OR pres.drug LIKE '%trandolapril%'
      OR pres.drug LIKE '%moexipril%'
    )
)

SELECT
  STDDEV(duration_days) AS sd_ace_inhibitor_duration_days
FROM
  ace_inhibitors;