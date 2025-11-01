WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'M' AND p.anchor_age BETWEEN 90 AND 100
), AdmissionInfo AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
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
    d.icd_code LIKE 'I20%' -- Chest pain ICD-10 code
    AND d.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
), TroponinInfo AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum AS troponin_value
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents` AS l
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.d_labitems` AS d_lab
    ON l.itemid = d_lab.itemid
  WHERE
    d_lab.label = 'Troponin I'
    AND l.subject_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND l.valuenum IS NOT NULL
    AND l.valuenum > 0 -- Assuming elevated Troponin I is > 0
), InitialTroponin AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    MIN(t.charttime) AS first_charttime
  FROM
    TroponinInfo AS t
  GROUP BY
    t.subject_id,
    t.hadm_id
), FirstTroponinValues AS (
  SELECT
    t.subject_id,
    t.hadm_id,
    t.troponin_value
  FROM
    TroponinInfo AS t
  INNER JOIN
    InitialTroponin AS it
    ON t.subject_id = it.subject_id AND t.hadm_id = it.hadm_id AND t.charttime = it.first_charttime
)
SELECT
  PERCENTILE_CONT(0.25, ftv.troponin_value) AS p25,
  PERCENTILE_CONT(0.50, ftv.troponin_value) AS p50,
  PERCENTILE_CONT(0.75, ftv.troponin_value) AS p75,
  MIN(ftv.troponin_value) AS min_value,
  MAX(ftv.troponin_value) AS max_value
FROM
  FirstTroponinValues AS ftv
INNER JOIN
  AdmissionInfo AS ai
  ON ftv.subject_id = ai.subject_id AND ftv.hadm_id = ai.hadm_id
INNER JOIN
  DiagnosisInfo AS di
  ON ftv.subject_id = di.subject_id AND ftv.hadm_id = di.hadm_id
WHERE
  ai.admittime <= ftv.charttime;