WITH first_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
),
first_admission_per_patient AS (
  SELECT
    subject_id,
    hadm_id,
    gender,
    anchor_age,
    admittime,
    hospital_expire_flag
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime ASC) AS rn
    FROM
      first_admissions
  )
  WHERE rn = 1
),
dapt_patients AS (
  SELECT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM
    first_admission_per_patient fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr_asp
    ON fa.subject_id = pr_asp.subject_id AND fa.hadm_id = pr_asp.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr_p2y12
    ON fa.subject_id = pr_p2y12.subject_id AND fa.hadm_id = pr_p2y12.hadm_id
  WHERE
    LOWER(pr_asp.drug) LIKE '%aspirin%'
    AND (
      LOWER(pr_p2y12.drug) LIKE '%clopidogrel%'
      OR LOWER(pr_p2y12.drug) LIKE '%ticagrelor%'
      OR LOWER(pr_p2y12.drug) LIKE '%prasugrel%'
    )
)
SELECT
  STDDEV_SAMP(CAST(hospital_expire_flag AS FLOAT64)) AS sd_in_hospital_mortality
FROM
  dapt_patients
;