WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age,
    d_diag.long_title AS diagnosis
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
    ON p.subject_id = diag.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 76
    AND d_diag.long_title LIKE '%diabetes%'
    AND d_diag.long_title LIKE '%heart failure%'
),
MedicationInitiation AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.drug,
    p.route,
    p.drug_type
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug LIKE '%metformin%'
    OR p.drug LIKE '%sulfonylurea%'
    OR p.drug LIKE '%DPP-4%'
    OR p.drug LIKE '%SGLT2%'
    OR p.drug LIKE '%thiazolidinedione%'
),
TimeWindows AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    drug,
    CASE
      WHEN starttime BETWEEN (
        SELECT
          adm.admittime
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
        WHERE
          adm.hadm_id = p.hadm_id
      ) AND (
        SELECT
          TIMESTAMP_ADD((
            SELECT
              adm.admittime
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
            WHERE
              adm.hadm_id = p.hadm_id
          ), INTERVAL 72 HOUR)
      )
      THEN 'First 72h'
      WHEN starttime > (
        SELECT
          TIMESTAMP_ADD((
            SELECT
              adm.admittime
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
            WHERE
              adm.hadm_id = p.hadm_id
          ), INTERVAL 72 HOUR)
      ) AND starttime <= (
        SELECT
          TIMESTAMP_ADD((
            SELECT
              adm.admittime
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
            WHERE
              adm.hadm_id = p.hadm_id
          ), INTERVAL 120 HOUR)
      )
      THEN 'Last 48h'
      ELSE 'Other'
    END AS time_window
  FROM MedicationInitiation AS p
),
PatientCounts AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON adm.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
)
SELECT
  tw.drug,
  tw.time_window,
  COUNT(DISTINCT tw.subject_id) / (
    SELECT
      total_patients
    FROM PatientCounts
  ) * 100 AS initiation_rate
FROM TimeWindows AS tw
WHERE
  tw.time_window IN ('First 72h', 'Last 48h')
GROUP BY
  tw.drug,
  tw.time_window
ORDER BY
  tw.drug,
  tw.time_window;