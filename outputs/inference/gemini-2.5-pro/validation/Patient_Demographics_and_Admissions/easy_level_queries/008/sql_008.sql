WITH first_pci_admissions AS (
  -- Step 1: Identify the very first hospital admission for a PCI procedure
  -- for each patient within the specified demographic.
  SELECT
    pat.subject_id,
    adm.hadm_id,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON pat.subject_id = adm.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
    ON adm.hadm_id = proc.hadm_id
  WHERE
    -- Filter for male patients
    pat.gender = 'M'
    -- Filter for age between 52 and 62 at the time of admission
    AND (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year + pat.anchor_age) BETWEEN 52 AND 62
    -- Filter for PCI procedure codes (ICD-9 and ICD-10)
    AND (
      (proc.icd_version = 9 AND proc.icd_code IN ('00.66', '36.06', '36.07'))
      OR (proc.icd_version = 10 AND proc.icd_code LIKE '027%')
    )
  -- The QUALIFY clause filters the results of a window function.
  -- Here, it keeps only the first admission (ranked by time) for each patient.
  QUALIFY ROW_NUMBER() OVER (PARTITION BY pat.subject_id ORDER BY adm.admittime) = 1
),

next_admission_times AS (
  -- Step 2: For every hospital admission, find the start time of the next one.
  -- The LEAD function looks ahead in the partition.
  SELECT
    hadm_id,
    LEAD(admittime, 1) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions`
)

-- Step 3: Calculate the 30-day readmission rate for the cohort.
SELECT
  -- Count the total number of patients in the cohort
  COUNT(pci.hadm_id) AS number_of_patients,
  -- Calculate the average of the readmission flag to get the rate
  AVG(
    CASE
      -- Check if there is a next admission and if it's within 30 days of discharge
      WHEN next_adm.next_admittime IS NOT NULL
        AND DATETIME_DIFF(next_adm.next_admittime, pci.dischtime, DAY) <= 30
        AND DATETIME_DIFF(next_adm.next_admittime, pci.dischtime, DAY) >= 0 -- ensures next admission is after discharge
        THEN 1
      ELSE 0
    END
  ) AS avg_30_day_readmission_rate
FROM
  first_pci_admissions AS pci
LEFT JOIN
  next_admission_times AS next_adm
  ON pci.hadm_id = next_adm.hadm_id;