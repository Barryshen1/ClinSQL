WITH AKI_Patients AS (
  -- Identify patients with AKI based on ICD-10 codes
  SELECT DISTINCT
    p.subject_id,
    p.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age >= 64
    AND p.anchor_age <= 74
    AND d.icd_code LIKE 'N17%' -- AKI ICD-10 codes
),
Imaging_Counts AS (
  -- Count diagnostic imaging studies per admission
  SELECT
    a.hadm_id,
    COUNT(h.hcpcs_cd) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` AS h
    ON a.hadm_id = h.hadm_id
  WHERE
    a.hadm_id IN (SELECT hadm_id FROM AKI_Patients)
    AND h.hcpcs_cd LIKE '7%' -- Diagnostic imaging HCPCS codes
  GROUP BY
    a.hadm_id
),
Admission_Duration AS (
  -- Calculate admission duration in days
  SELECT
    hadm_id,
    DATE_DIFF(dischtime, admittime, DAY) AS admission_duration
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE
    hadm_id IN (SELECT hadm_id FROM AKI_Patients)
),
Diagnosis_Priority AS (
  -- Determine if AKI is primary or secondary diagnosis
  SELECT
    hadm_id,
    MIN(seq_num) AS min_seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    hadm_id IN (SELECT hadm_id FROM AKI_Patients)
    AND icd_code LIKE 'N17%'
  GROUP BY
    hadm_id
)
SELECT
  CASE
    WHEN dp.min_seq_num = 1 THEN 'Primary'
    ELSE 'Secondary'
  END AS diagnosis_priority,
  CASE
    WHEN ad.admission_duration BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN ad.admission_duration BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE 'Other'
  END AS admission_duration_group,
  PERCENTILE_CONT(ic.imaging_count, 0.5) AS median_imaging_count,
  PERCENTILE_CONT(ic.imaging_count, 0.25) AS iqr_25_imaging_count,
  PERCENTILE_CONT(ic.imaging_count, 0.75) AS iqr_75_imaging_count
FROM Imaging_Counts AS ic
JOIN Admission_Duration AS ad
  ON ic.hadm_id = ad.hadm_id
JOIN Diagnosis_Priority AS dp
  ON ic.hadm_id = dp.hadm_id
WHERE
  ad.admission_duration BETWEEN 1 AND 7
GROUP BY
  diagnosis_priority,
  admission_duration_group
ORDER BY
  diagnosis_priority,
  admission_duration_group;