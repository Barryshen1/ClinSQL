WITH PatientInfo AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age AS age,
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
    AND p.anchor_age BETWEEN 64 AND 74
    AND d.long_title LIKE '%diabetes%'
    AND d.long_title LIKE '%HF%'
),
MedicationInfo AS (
  SELECT
    p.subject_id,
    p.starttime,
    p.drug,
    p.drug_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug_type = 'Medication'
),
MedicationClass AS (
  SELECT
    subject_id,
    starttime,
    drug,
    CASE
      WHEN drug LIKE '%insulin%' THEN 'insulin'
      WHEN drug LIKE '%metformin%' THEN 'metformin'
      WHEN drug LIKE '%sulfonylurea%' THEN 'sulfonylureas'
      WHEN drug LIKE '%DPP-4%' THEN 'DPP-4'
      WHEN drug LIKE '%SGLT2%' THEN 'SGLT2'
      WHEN drug LIKE '%GLP-1%' THEN 'GLP-1'
      WHEN drug LIKE '%TZD%' THEN 'TZDs'
      ELSE 'other'
    END AS med_class
  FROM
    MedicationInfo
),
TimeWindows AS (
  SELECT
    subject_id,
    starttime,
    med_class,
    CASE
      WHEN starttime BETWEEN 0 AND 12 THEN 'first 12h'
      WHEN starttime BETWEEN 12 AND 48 THEN 'final 48h'
      ELSE 'other'
    END AS time_window
  FROM
    MedicationClass
),
InitiationCounts AS (
  SELECT
    med_class,
    time_window,
    COUNT(DISTINCT subject_id) AS initiation_count
  FROM
    TimeWindows
  WHERE
    time_window IN ('first 12h', 'final 48h')
  GROUP BY
    med_class,
    time_window
),
TotalPatients AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients
  FROM
    PatientInfo
)
SELECT
  ic.med_class,
  ic.time_window,
  ic.initiation_count,
  (
    ic.initiation_count / tp.total_patients
  ) * 100 AS initiation_percentage
FROM
  InitiationCounts AS ic
CROSS JOIN
  TotalPatients AS tp
ORDER BY
  ic.med_class,
  ic.time_window;