WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
), MedicationInfo AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug LIKE '%anticoagulant%'
), LOSCalculation AS (
  SELECT
    ai.subject_id,
    ai.hadm_id,
    ai.admittime,
    ai.dischtime,
    ai.deathtime,
    ai.hospital_expire_flag,
    mi.drug
  FROM
    AdmissionInfo AS ai
  JOIN
    MedicationInfo AS mi
    ON ai.subject_id = mi.subject_id AND ai.hadm_id = mi.hadm_id
)
SELECT
  STDDEV(DATE_DIFF(dischtime, admitime, DAY)) AS sd_los
FROM
  LOSCalculation AS lc
JOIN
  PatientInfo AS pi
  ON lc.subject_id = pi.subject_id
WHERE
  pi.gender = 'F' AND pi.anchor_age BETWEEN 52 AND 62;