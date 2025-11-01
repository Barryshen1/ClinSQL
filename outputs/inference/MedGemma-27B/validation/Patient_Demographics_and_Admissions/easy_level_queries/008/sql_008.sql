WITH FirstPCI AS (
  -- Identify patients who had their first PCI
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY a.admittime ASC) as rn
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type = 'EMERGENCY' -- Assuming PCI is typically an emergency admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pi
      WHERE pi.subject_id = p.subject_id
        AND pi.hadm_id = a.hadm_id
        AND pi.icd_code LIKE '332%' -- ICD-10 codes for Percutaneous Cardiovascular Intervention
    )
),
PCI_Admissions AS (
  -- Filter for the first PCI admission for each patient
  SELECT
    subject_id,
    hadm_id,
    admittime
  FROM FirstPCI
  WHERE rn = 1
),
Readmissions AS (
  -- Identify readmissions within 30 days
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    PCI_Admissions AS pci
    ON a.subject_id = pci.subject_id
  WHERE
    a.hadm_id != pci.hadm_id
    AND a.admittime BETWEEN pci.admittime + INTERVAL '30' DAY AND pci.admittime + INTERVAL '30' DAY
)
SELECT
  COUNT(DISTINCT r.subject_id) * 100.0 / COUNT(DISTINCT pci.subject_id) AS readmission_rate
FROM
  PCI_Admissions AS pci
LEFT JOIN
  Readmissions AS r
  ON pci.subject_id = r.subject_id;