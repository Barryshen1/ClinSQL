WITH male_medicare_patients AS (
  SELECT
    p.subject_id,
    p.anchor_age,
    p.anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 90 AND 100
),

transfer_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.insurance
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    male_medicare_patients mmp ON a.subject_id = mmp.subject_id
  WHERE
    a.insurance = 'Medicare'
    AND a.admission_type = 'TRANSFER'
),

principal_esrd_diagnoses AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    d.seq_num = 1  -- Principal diagnosis
    AND (
      (d.icd_version = 9 AND d.icd_code = '585.6') OR
      (d.icd_version = 10 AND d.icd_code = 'N18.6')
    )
)

SELECT
  COUNT(DISTINCT ta.hadm_id) AS number_of_admissions
FROM
  transfer_admissions ta
JOIN
  principal_esrd_diagnoses ped ON ta.subject_id = ped.subject_id AND ta.hadm_id = ped.hadm_id;