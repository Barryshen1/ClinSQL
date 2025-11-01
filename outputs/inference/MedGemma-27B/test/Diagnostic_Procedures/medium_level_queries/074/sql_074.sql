WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.anchor_age = 45
    AND p.gender = 'F'
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
  WHERE
    a.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
), DiagnosisInfo AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
  WHERE
    d.icd_code = 'I63.9'
    AND d.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
), ProcedureInfo AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.chartdate,
    pr.icd_code
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
  WHERE
    pr.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
), ICUStayInfo AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.intime,
    ic.outtime,
    ic.los
  FROM
    `physionet-data.mimiciv_3_1_hosp.icustays` AS ic
  WHERE
    ic.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
)
SELECT
  CASE
    WHEN ic.los BETWEEN 1 AND 4
    THEN '1-4 days'
    WHEN ic.los BETWEEN 5 AND 7
    THEN '5-7 days'
    ELSE 'Other'
  END AS los_group,
  ic.last_careunit AS icu_unit,
  COUNT(pr.icd_code) AS num_procedures,
  AVG(COUNT(pr.icd_code)) OVER (PARTITION BY ic.last_careunit, los_group) AS mean_procedures,
  MIN(COUNT(pr.icd_code)) OVER (PARTITION BY ic.last_careunit, los_group) AS min_procedures,
  MAX(COUNT(pr.icd_code)) OVER (PARTITION BY ic.last_careunit, los_group) AS max_procedures
FROM
  ICUStayInfo AS ic
LEFT JOIN
  ProcedureInfo AS pr
  ON ic.subject_id = pr.subject_id AND ic.hadm_id = pr.hadm_id
WHERE
  ic.los BETWEEN 1 AND 7
  AND ic.last_careunit IS NOT NULL
GROUP BY
  los_group,
  ic.last_careunit
ORDER BY
  ic.last_careunit,
  los_group;