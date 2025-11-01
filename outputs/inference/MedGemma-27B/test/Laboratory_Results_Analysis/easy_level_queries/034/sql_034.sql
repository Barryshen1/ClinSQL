WITH HeartFailureAdmissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    di.long_title LIKE '%heart failure%'
    AND a.hadm_id IN (
      SELECT
        p.subject_id
      FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
      WHERE
        p.gender = 'M' AND p.anchor_age = 65
    )
), SerumSodiumMeasurements AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS sodium_value,
    le.charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Sodium'
    AND le.subject_id IN (
      SELECT
        subject_id
      FROM HeartFailureAdmissions
    )
    AND le.hadm_id IN (
      SELECT
        hadm_id
      FROM HeartFailureAdmissions
    )
)
SELECT
  MIN(sodium_value) AS min_sodium
FROM SerumSodiumMeasurements;