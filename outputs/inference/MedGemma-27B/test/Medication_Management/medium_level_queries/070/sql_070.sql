WITH PatientInfo AS (
  -- Select subject_id and age for patients matching the criteria
  SELECT
    p.subject_id,
    p.anchor_age AS age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F' AND p.anchor_age BETWEEN 68 AND 78
),
MedicationOrders AS (
  -- Select relevant medication orders within the first 48 hours of admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.drug,
    p.starttime,
    p.stoptime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
    ON a.hadm_id = p.hadm_id
  WHERE
    a.hadm_id IN (
      SELECT
        subject_id
      FROM
        PatientInfo
    )
    AND p.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND (
      p.drug LIKE '%metformin%' OR p.drug LIKE '%sulfonylurea%' OR p.drug LIKE '%DPP-4%' OR p.drug LIKE '%SGLT2%'
    )
),
First48hMedications AS (
  -- Count medications in the first 48 hours
  SELECT
    subject_id,
    hadm_id,
    drug,
    COUNT(*) AS count_first48h
  FROM
    MedicationOrders
  GROUP BY
    subject_id,
    hadm_id,
    drug
),
Last12hMedications AS (
  -- Count medications in the last 12 hours
  SELECT
    subject_id,
    hadm_id,
    drug,
    COUNT(*) AS count_last12h
  FROM
    MedicationOrders
  WHERE
    starttime BETWEEN TIMESTAMP_SUB(admittime, INTERVAL 12 HOUR) AND admittime
  GROUP BY
    subject_id,
    hadm_id,
    drug
),
CombinedMedications AS (
  -- Combine first 48h and last 12h medication counts
  SELECT
    subject_id,
    hadm_id,
    drug,
    COALESCE(count_first48h, 0) AS count_first48h,
    COALESCE(count_last12h, 0) AS count_last12h
  FROM
    First48hMedications
  FULL OUTER JOIN
    Last12hMedications
    ON First48hMedications.subject_id = Last12hMedications.subject_id
    AND First48hMedications.hadm_id = Last12hMedications.hadm_id
    AND First48hMedications.drug = Last12hMedications.drug
),
TotalPatients AS (
  -- Count total number of patients
  SELECT
    COUNT(DISTINCT subject_id) AS total_patients
  FROM
    PatientInfo
),
MedicationPrevalence AS (
  -- Calculate prevalence for each medication
  SELECT
    drug,
    SUM(CASE WHEN count_first48h > 0 THEN 1 ELSE 0 END) * 100.0 / TotalPatients.total_patients AS prevalence_first48h,
    SUM(CASE WHEN count_last12h > 0 THEN 1 ELSE 0 END) * 100.0 / TotalPatients.total_patients AS prevalence_last12h,
    (SUM(CASE WHEN count_first48h > 0 THEN 1 ELSE 0 END) - SUM(CASE WHEN count_last12h > 0 THEN 1 ELSE 0 END)) * 100.0 / TotalPatients.total_patients AS net_change
  FROM
    CombinedMedications
  CROSS JOIN
    TotalPatients
  GROUP BY
    drug
)
SELECT
  drug,
  prevalence_first48h,
  prevalence_last12h,
  net_change
FROM
  MedicationPrevalence
ORDER BY
  drug;