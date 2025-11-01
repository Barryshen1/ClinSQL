WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    di.hadm_id,
    d.long_title AS diagnosis
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON p.subject_id = di.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 48 AND 58
    AND d.long_title LIKE '%pneumonia%'
), MedicationEvents AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.charttime,
    e.medication
  FROM
    PatientInfo AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.emar` AS e
    ON p.subject_id = e.subject_id
    AND p.hadm_id = e.hadm_id
  WHERE
    e.charttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 24 HOUR)
), MedicationComplexity AS (
  SELECT
    subject_id,
    hadm_id,
    COUNT(DISTINCT medication) AS num_meds
  FROM
    MedicationEvents
  GROUP BY
    subject_id,
    hadm_id
), PatientOutcomes AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.dischtime,
    p.deathtime,
    p.hospital_expire_flag,
    mc.num_meds,
    CASE
      WHEN mc.num_meds >= (SELECT PERCENTILE_CONT(num_meds, 0.75) FROM MedicationComplexity)
      THEN 1
      ELSE 0
    END AS is_high_complexity
  FROM
    PatientInfo AS p
  JOIN
    MedicationComplexity AS mc
    ON p.subject_id = mc.subject_id
    AND p.hadm_id = mc.hadm_id
), ICUStays AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los
  FROM
    PatientInfo AS p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON p.subject_id = i.subject_id
    AND p.hadm_id = i.hadm_id
), SerotonergicInteractionRisk AS (
  SELECT
    p.subject_id,
    p.hadm_id
  FROM
    PatientInfo AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.;