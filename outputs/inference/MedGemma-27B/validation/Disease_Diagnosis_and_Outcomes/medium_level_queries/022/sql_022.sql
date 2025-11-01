WITH PatientCohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND a.hospital_expire_flag = 1
), SepsisCohort AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.admittime,
    pc.dischtime,
    pc.deathtime,
    pc.hospital_expire_flag,
    di.icd_code
  FROM PatientCohort AS pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON pc.subject_id = di.subject_id AND pc.hadm_id = di.hadm_id
  WHERE
    di.icd_code = 'E86'
), SepsisNoShockCohort AS (
  SELECT
    sc.subject_id,
    sc.hadm_id,
    sc.admittime,
    sc.dischtime,
    sc.deathtime,
    sc.hospital_expire_flag,
    sc.icd_code
  FROM SepsisCohort AS sc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
    ON sc.subject_id = di2.subject_id AND sc.hadm_id = di2.hadm_id
  WHERE
    di2.icd_code IS NULL OR di2.icd_code != 'R65.21'
), ICUStatus AS (
  SELECT
    snsc.subject_id,
    snsc.hadm_id,
    snsc.admittime,
    snsc.dischtime,
    snsc.deathtime,
    snsc.hospital_expire_flag,
    snsc.icd_code,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM SepsisNoShockCohort AS snsc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON snsc.subject_id = i.subject_id AND snsc.hadm_id = i.hadm_id
  WHERE
    i.intime < snsc.admittime + INTERVAL '1' DAY
), FinalCohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.admittime,
    icu.dischtime,
    icu.deathtime,
    icu.hospital_expire_flag,
    icu.icd_code,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    CASE
      WHEN icu.intime < icu.admittime THEN 'Day 1 ICU'
      ELSE 'Not Day 1 ICU'
    END AS day_1_icu_status,
    CASE
      WHEN icu.los <= 7 THEN 'LOS <= 7 days'
      ELSE 'LOS > 7 days'
    END AS los_group
  FROM ICUStatus AS icu
)
SELECT
  day_1_icu_status,
  los_group,
  COUNT(subject_id) AS patient_count,
  SUM(hospital_expire_flag) * 100.0 / COUNT(subject_id) AS mortality_percentage,
  AVG(los) AS median_los
FROM FinalCohort
GROUP BY
  day_1_icu_status,
  los_group
ORDER BY
  day_1_icu_status,
  los_group;