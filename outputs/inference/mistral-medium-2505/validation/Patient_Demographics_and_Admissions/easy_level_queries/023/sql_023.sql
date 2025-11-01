WITH pci_patients AS (
  -- Get patients who underwent PCI
  SELECT
    p.subject_id,
    p.hadm_id,  -- Ensure hadm_id is included
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc
    ON a.subject_id = proc.subject_id AND a.hadm_id = proc.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d_proc
    ON proc.icd_code = d_proc.icd_code AND proc.icd_version = d_proc.icd_version
  WHERE
    p.gender = 'M'
    -- Age between 68-78 at admission (anchor_age + years since anchor_year)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 68 AND 78
    -- Filter for PCI procedures (ICD-9: 36.01-36.09, ICD-10: 02703ZZ, 02704ZZ, etc.)
    AND (
      (proc.icd_version = 9 AND proc.icd_code BETWEEN '36.01' AND '36.09')
      OR
      (proc.icd_version = 10 AND proc.icd_code IN ('02703ZZ', '02704ZZ'))
    )
),

icu_stays AS (
  -- Get ICU stays for these patients
  SELECT
    p.subject_id,
    p.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    TIMESTAMP_DIFF(i.outtime, i.intime, DAY) + 1 AS los_days  -- +1 to count inclusive days
  FROM
    pci_patients p
  JOIN
    `physionet-data.mimiciv_3_1_icu.icustays` i
    ON p.subject_id = i.subject_id AND p.hadm_id = i.hadm_id
  WHERE
    i.outtime IS NOT NULL  -- Exclude ongoing ICU stays
)

-- Calculate median ICU LOS per stay
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_icu_los_days
FROM
  icu_stays;