WITH first_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  WHERE
    admittime = (
      SELECT MIN(admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = a.subject_id
    )
),
cabg_admissions AS (
  SELECT DISTINCT
    fa.subject_id,
    fa.hadm_id,
    fa.hospital_expire_flag
  FROM
    first_admissions fa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON fa.hadm_id = proc.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dproc
    ON proc.icd_code = dproc.icd_code
    AND proc.icd_version = dproc.icd_version
  WHERE
    LOWER(dproc.long_title) LIKE '%cabg%'
    OR LOWER(dproc.long_title) LIKE '%coronary artery bypass%'
),
eligible_patients AS (
  SELECT
    cabg.subject_id,
    cabg.hadm_id,
    cabg.hospital_expire_flag
  FROM
    cabg_admissions cabg
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON cabg.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 35 AND 45
)

SELECT
  AVG(hospital_expire_flag) AS in_hospital_mortality
FROM
  eligible_patients;