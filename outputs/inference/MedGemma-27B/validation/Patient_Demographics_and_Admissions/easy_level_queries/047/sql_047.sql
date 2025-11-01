WITH AKI_Patients AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
    AND di.long_title LIKE '%acute kidney injury%'
), ICU_Stays AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime,
    s.outtime,
    s.los
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  WHERE
    s.subject_id IN (
      SELECT
        subject_id
      FROM AKI_Patients
    )
), First_ICU_LOS AS (
  SELECT
    subject_id,
    stay_id,
    intime,
    outtime,
    los
  FROM ICU_Stays
  WHERE
    stay_id IN (
      SELECT
        MIN(stay_id)
      FROM ICU_Stays
      GROUP BY
        subject_id
    )
)
SELECT
  PERCENTILE_CONT(0.25, los) AS percentile_25_first_icu_los
FROM First_ICU_LOS;