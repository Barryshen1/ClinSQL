WITH PatientCohort AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age >= 88
    AND p.anchor_age <= 98
    AND d.icd_code = '410' -- AMI code
    AND a.hadm_id IN (
      SELECT DISTINCT
        a.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
        ON a.hadm_id = i.hadm_id
    )
),
CompositeRisk AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    (
      CASE
        WHEN d.icd_code = '410' THEN 1
        ELSE 0
      END
    ) AS ami_flag,
    (
      CASE
        WHEN d.icd_code = 'N17' THEN 1
        ELSE 0
      END
    ) AS aki_flag,
    (
      CASE
        WHEN d.icd_code = 'J81' THEN 1
        ELSE 0
      END
    ) AS ards_flag,
    (
      CASE
        WHEN a.hospital_expire_flag = 1 THEN 1
        ELSE 0
      END
    ) AS mortality_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
),
Mortality AS (
  SELECT
    subject_id,
    hadm_id,
    (
      CASE
        WHEN a.hospital_expire_flag = 1 THEN 1
        ELSE 0
      END
    ) AS mortality_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
),
AKI AS (
  SELECT
    subject_id,
    hadm_id,
    (
      CASE
        WHEN d.icd_code = 'N17' THEN 1
        ELSE 0
      END
    ) AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
),
ARDS AS (
  SELECT
    subject_id,
    hadm_id,
    (
      CASE
        WHEN d.icd_code = 'J81' THEN 1
        ELSE 0
      END
    ) AS ards_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM PatientCohort
    )
),
Survival AS (
  SELECT
    a.subject_id,
    a.;