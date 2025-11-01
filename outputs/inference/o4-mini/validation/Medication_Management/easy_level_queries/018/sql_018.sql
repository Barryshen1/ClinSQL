SELECT
  MAX(DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY)) AS max_digoxin_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.patients` AS pt
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pt.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON adm.subject_id = p.subject_id
   AND adm.hadm_id = p.hadm_id
WHERE
  pt.gender = 'M'
  AND pt.anchor_age BETWEEN 82 AND 92
  AND LOWER(p.drug) LIKE '%digoxin%'
  AND p.starttime IS NOT NULL
  AND p.stoptime IS NOT NULL
  -- Ensure the prescription falls within the hospitalization window
  AND p.starttime BETWEEN adm.admittime AND adm.dischtime
  AND p.stoptime BETWEEN adm.admittime AND adm.dischtime;