WITH first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS admission_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

dapt_patients AS (
  SELECT DISTINCT
    p.subject_id,
    fa.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    first_admissions fa ON p.subject_id = fa.subject_id AND fa.admission_rank = 1
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pres ON p.subject_id = pres.subject_id AND fa.hadm_id = pres.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND (
      LOWER(pres.drug) LIKE '%aspirin%'
      OR LOWER(pres.drug) LIKE '%plavix%'
      OR LOWER(pres.drug) LIKE '%clopidogrel%'
      OR LOWER(pres.drug) LIKE '%brilinta%'
      OR LOWER(pres.drug) LIKE '%ticagrelor%'
      OR LOWER(pres.drug) LIKE '%effient%'
      OR LOWER(pres.drug) LIKE '%prasugrel%'
    )
)

SELECT
  STDDEV(hospital_expire_flag) AS sd_in_hospital_mortality
FROM
  first_admissions fa
JOIN
  dapt_patients dp ON fa.subject_id = dp.subject_id AND fa.hadm_id = dp.hadm_id
WHERE
  fa.admission_rank = 1;