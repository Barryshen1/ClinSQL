WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    anchor_age = 67
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.los,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  INNER JOIN
    PatientInfo AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 62 AND 72
), DiagnosticEvents AS (
  SELECT
    a.hadm_id,
    a.charttime,
    d.label AS diagnostic_label,
    d.category AS diagnostic_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` AS a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_items` AS d
    ON a.itemid = d.itemid
  WHERE
    d.category = 'Diagnostic'
), NonInvasiveDiagnostics AS (
  SELECT
    hadm_id,
    diagnostic_label,
    diagnostic_category
  FROM
    DiagnosticEvents
  WHERE
    diagnostic_category IN ('Imaging', 'ECG/EEG/PFT')
), ICUStatus AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN intime IS NOT NULL THEN 1 ELSE 0 END) AS icu_status
  FROM
    `physionet-data.mimiciv_3_1_hosp.icustays`
  GROUP BY
    hadm_id
), AdmissionLOS AS (
  SELECT
    hadm_id,
    CASE
      WHEN los BETWEEN 1 AND 3
      THEN '1-3 days'
      WHEN los BETWEEN 4 AND 7
      THEN '4-7 days'
      ELSE 'Other'
    END AS los_category
  FROM
    AdmissionInfo
)
SELECT
  a.los_category,
  ic.icu_status,
  COUNT(DISTINCT nid.hadm_id) AS num_admissions,
  AVG(COUNT(DISTINCT nid.hadm_id)) AS mean_non_invasive_diagnostics
FROM
  AdmissionLOS AS a
INNER JOIN
  NonInvasiveDiagnostics AS nid
  ON a.hadm_id = nid.hadm_id
INNER JOIN
  ICUStatus AS ic
  ON a.hadm_id = ic.hadm_id
GROUP BY
  a.los_category,
  ic.icu_status
ORDER BY
  a.los_category,
  ic.icu_status;