WITH pci_codes AS (
  -- Identify PCI ICD codes
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
  WHERE LOWER(long_title) LIKE '%percutaneous coronary intervention%'
     OR LOWER(long_title) LIKE '%coronary angioplasty%'
     OR LOWER(long_title) LIKE '%pci%'
),
first_pci AS (
  -- Find first PCI for each patient
  SELECT
    p.subject_id,
    pr.hadm_id,
    pr.chartdate AS pci_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
    ON p.subject_id = pr.subject_id
  JOIN pci_codes pc
    ON pr.icd_code = pc.icd_code AND pr.icd_version = pc.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),
first_pci_admission AS (
  -- For each patient, select their earliest PCI (first PCI admission)
  SELECT
    subject_id,
    hadm_id,
    MIN(pci_date) AS first_pci_date
  FROM first_pci
  GROUP BY subject_id, hadm_id
),
index_admissions AS (
  -- Get admission/discharge times for first PCI admissions
  SELECT
    f.subject_id,
    f.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM first_pci_admission f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.subject_id = a.subject_id AND f.hadm_id = a.hadm_id
),
eligible_patients AS (
  -- Exclude patients who died during index admission
  SELECT *
  FROM index_admissions
  WHERE hospital_expire_flag = 0
    AND (deathtime IS NULL OR deathtime > dischtime)
),
readmissions AS (
  -- For each eligible patient, check for readmission within 30 days
  SELECT
    e.subject_id,
    e.hadm_id AS index_hadm_id,
    e.dischtime,
    MIN(a.admittime) AS readmit_time
  FROM eligible_patients e
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON e.subject_id = a.subject_id
    AND a.admittime > e.dischtime
    AND a.admittime <= DATETIME_ADD(e.dischtime, INTERVAL 30 DAY)
  GROUP BY e.subject_id, e.hadm_id, e.dischtime
),
final AS (
  -- Mark patients with/without 30-day readmission
  SELECT
    ep.subject_id,
    ep.hadm_id,
    CASE WHEN r.readmit_time IS NOT NULL THEN 1 ELSE 0 END AS readmitted_30d
  FROM eligible_patients ep
  LEFT JOIN readmissions r
    ON ep.subject_id = r.subject_id AND ep.hadm_id = r.index_hadm_id
)
SELECT
  COUNTIF(readmitted_30d = 1) AS num_readmitted_30d,
  COUNT(*) AS num_eligible_patients,
  SAFE_DIVIDE(COUNTIF(readmitted_30d = 1), COUNT(*)) AS avg_30d_readmission_rate
FROM final;