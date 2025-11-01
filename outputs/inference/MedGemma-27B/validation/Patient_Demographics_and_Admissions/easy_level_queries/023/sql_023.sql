WITH RelevantPatients AS (
  SELECT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 68 AND 78
), PatientProcedures AS (
  SELECT
    p.subject_id,
    p.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    d.long_title LIKE '%PCI%'
), PatientICUStays AS (
  SELECT
    ic.subject_id,
    ic.hadm_id,
    ic.stay_id,
    ic.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  INNER JOIN
    RelevantPatients AS rp
    ON ic.subject_id = rp.subject_id
  INNER JOIN
    PatientProcedures AS pp
    ON ic.subject_id = pp.subject_id AND ic.hadm_id = pp.hadm_id
)
SELECT
  PERCENTILE_CONT(0.5, los) AS median_icu_los
FROM
  PatientICUStays;