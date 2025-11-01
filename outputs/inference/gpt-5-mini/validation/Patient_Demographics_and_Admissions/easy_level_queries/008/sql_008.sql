WITH pci_proc_candidates AS (
  -- Identify ICD procedure entries whose description likely corresponds to PCI
  SELECT
    p.subject_id,
    p.hadm_id,
    p.chartdate,
    p.icd_code,
    p.icd_version,
    d.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
  ON
    p.icd_code = d.icd_code
    AND p.icd_version = d.icd_version
  WHERE
    -- look for descriptions that indicate percutaneous coronary interventions / stenting
    LOWER(d.long_title) LIKE '%percutaneous%'
    AND (
      LOWER(d.long_title) LIKE '%coronar%'
      OR LOWER(d.long_title) LIKE '%stent%'
      OR LOWER(d.long_title) LIKE '%pci%'
      OR LOWER(d.long_title) LIKE '%transluminal%'
    )
),

first_pci_per_subject AS (
  -- For each patient, pick the earliest PCI procedure observed in the DB
  SELECT
    subject_id,
    hadm_id,
    chartdate,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY chartdate, hadm_id) AS rn
  FROM
    pci_proc_candidates
),

index_pci_admissions AS (
  -- Keep only the first PCI per subject and join to the corresponding admission
  SELECT
    f.subject_id,
    f.hadm_id AS index_hadm_id,
    f.chartdate AS pci_date,
    a.admittime,
    a.dischtime
  FROM
    first_pci_per_subject f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    f.hadm_id = a.hadm_id
  WHERE
    f.rn = 1
    AND a.dischtime IS NOT NULL  -- need discharge to compute 30-day window
),

cohort AS (
  -- Restrict to male patients aged 52-62 (inclusive)
  SELECT
    ipa.*,
    p.gender,
    p.anchor_age
  FROM
    index_pci_admissions ipa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    ipa.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
),

readmission_flagged AS (
  -- For each index (first PCI) admission, determine if there is any readmission within 30 days
  SELECT
    c.*,
    CASE
      WHEN EXISTS (
        SELECT 1
        FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
        WHERE
          a2.subject_id = c.subject_id
          AND a2.hadm_id != c.index_hadm_id
          -- admission occurs after index discharge and within 30 days (inclusive)
          AND DATE(a2.admittime) > DATE(c.dischtime)
          AND DATE(a2.admittime) <= DATE_ADD(DATE(c.dischtime), INTERVAL 30 DAY)
      ) THEN 1 ELSE 0
    END AS readmit_within_30d
  FROM
    cohort c
)

SELECT
  COUNT(*) AS n_index_first_pci,
  SUM(readmit_within_30d) AS n_readmitted_within_30d,
  SAFE_DIVIDE(SUM(readmit_within_30d), COUNT(*)) AS readmission_rate_30d
FROM
  readmission_flagged;