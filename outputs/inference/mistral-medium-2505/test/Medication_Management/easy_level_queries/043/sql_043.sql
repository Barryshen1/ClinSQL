WITH female_patients_81_91 AS (
  SELECT
    p.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),

drug_patients AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE
    LOWER(pr.drug) LIKE '%hydralazine%'
    OR LOWER(pr.drug) LIKE '%isosorbide dinitrate%'
)

SELECT
  MIN(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS shortest_inpatient_duration_days
FROM
  `physionet-data.mimiciv_3_1_hosp.admissions` a
JOIN
  female_patients_81_91 f ON a.subject_id = f.subject_id AND a.hadm_id = f.hadm_id
JOIN
  drug_patients d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
WHERE
  a.dischtime IS NOT NULL
  AND a.admittime IS NOT NULL;