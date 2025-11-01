WITH AKI_Cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.hospital_expire_flag = 0 -- Exclude patients who died in the hospital
    AND EXISTS (
      SELECT
        1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE
        d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_code IN ('N17.9', 'N17.1', 'N17.2', 'N17.8', 'I12.0', 'I12.9') -- AKI ICD-10 codes
    )
), AKI_Mortality AS (
  SELECT
    aki.subject_id,
    aki.hadm_id,
    CASE
      WHEN a.deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS mortality_30_day
  FROM AKI_Cohort AS aki
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON aki.hadm_id = a.hadm_id
  WHERE
    a.deathtime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 30 DAY)
), AKI_Risk AS (
  SELECT
    aki.subject_id,
    aki.hadm_id,
    drg.drg_mortality AS risk_score
  FROM AKI_Cohort AS aki
  JOIN `physionet-data.mimiciv_3_1_hosp.drgcodes` AS drg
    ON aki.hadm_id = drg.hadm_id
), AKI_ARDS AS (
  SELECT
    aki.subject_id,
    aki.hadm_id
  FROM AKI_Cohort AS aki
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON aki.subject_id = d.subject_id
    AND aki.hadm_id = d.hadm_id
  WHERE
    d.icd_code = 'J80' -- ARDS ICD-10 code
), AKI_LOS AS (
  SELECT
    aki.subject_id,
    aki.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM AKI_Cohort AS aki
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON aki.hadm_id = a.hadm_id
), General_Cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND a.hospital_expire_flag = 0
), General_Mortality AS (
  SELECT
    gen.subject_id,
    gen.hadm_id,
    CASE
      WHEN a.deathtime IS NOT NULL THEN 1
      ELSE 0
    END AS mortality_30_day
  FROM General_Cohort AS gen
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON gen.hadm_id = a.hadm_id
  WHERE
    a.deathtime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 30 DAY)
), General;