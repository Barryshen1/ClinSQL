WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_location,
    a.discharge_location,
    a.los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.admission_location = 'EMERGENCY'
), DiagnosisCohort AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.los,
    pc.hospital_expire_flag,
    d.icd_code
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON pc.subject_id = d.subject_id
    AND pc.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'I50%' -- Heart failure
), ICUStayCohort AS (
  SELECT
    dc.subject_id,
    dc.hadm_id,
    dc.los,
    dc.hospital_expire_flag,
    ic.stay_id,
    ic.intime,
    ic.outtime
  FROM DiagnosisCohort AS dc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    ON dc.subject_id = ic.subject_id
    AND dc.hadm_id = ic.hadm_id
), ComorbidityCohort AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.los,
    ic.hospital_expire_flag,
    CASE
      WHEN d.icd_code LIKE 'N18%' THEN 1
      ELSE 0
    END AS has_ckd,
    CASE
      WHEN d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' THEN 1
      ELSE 0
    END AS has_diabetes
  FROM ICUStayCohort AS ic
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON ic.subject_id = d.subject_id
    AND ic.hadm_id = d.hadm_id
  WHERE
    d.icd_code LIKE 'N18%' OR d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%'
  GROUP BY
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.los,
    ic.hospital_expire_flag
), FinalCohort AS (
  SELECT
    cc.subject_id,
    cc.hadm_id,
    cc.stay_id,
    cc.los,
    cc.hospital;