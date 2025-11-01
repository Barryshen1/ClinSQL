WITH
  pci_codes AS (
    -- Step 1: Identify ICD codes for Percutaneous Coronary Intervention (PCI)
    SELECT
      icd_code,
      icd_version
    FROM
      `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
    WHERE
      (LOWER(long_title) LIKE '%coronary%' AND LOWER(long_title) LIKE '%angioplasty%')
      OR (LOWER(long_title) LIKE '%coronary%' AND LOWER(long_title) LIKE '%stent%')
      OR (LOWER(long_title) LIKE '%atherectomy%' AND LOWER(long_title) LIKE '%coronary%')
      OR LOWER(long_title) LIKE '%ptca%'
  ),
  pci_admissions AS (
    -- Step 2: Find all hospital admissions where a PCI procedure occurred
    SELECT DISTINCT
      p.subject_id,
      p.hadm_id
    FROM
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS p
    INNER JOIN
      pci_codes AS pc
      ON p.icd_code = pc.icd_code
      AND p.icd_version = pc.icd_version
  ),
  first_pci_admission_for_patient AS (
    -- Step 3: Determine the first PCI admission for each patient
    SELECT
      pa.subject_id,
      pa.hadm_id,
      a.admittime,
      a.dischtime,
      a.hospital_expire_flag,
      ROW_NUMBER() OVER (PARTITION BY pa.subject_id ORDER BY a.admittime) AS rn
    FROM
      pci_admissions AS pa
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS a
      ON pa.subject_id = a.subject_id
      AND pa.hadm_id = a.hadm_id
  ),
  cohort_admissions AS (
    -- Step 4: Filter to define the target cohort
    SELECT
      fpa.subject_id,
      fpa.hadm_id,
      fpa.admittime,
      fpa.dischtime,
      fpa.hospital_expire_flag
    FROM
      first_pci_admission_for_patient AS fpa
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.patients` AS pat
      ON fpa.subject_id = pat.subject_id
    WHERE
      fpa.rn = 1 -- Only the first PCI admission for each patient
      AND pat.gender = 'M' -- Men
      AND (pat.anchor_age + (EXTRACT(YEAR FROM fpa.admittime) - pat.anchor_year)) BETWEEN 52 AND 62 -- Aged 52-62 at admission
      AND fpa.hospital_expire_flag = 0 -- Exclude patients who died during the index admission
  ),
  readmissions_flagged AS (
    -- Step 5: Identify 30-day readmissions for the cohort
    SELECT
      ca.subject_id,
      ca.hadm_id AS index_hadm_id,
      ca.admittime AS index_admittime,
      ca.dischtime AS index_dischtime,
      -- Check for any subsequent admission within 30 days
      MAX(
        CASE
          WHEN
              next_adm.admittime IS NOT NULL
              AND next_adm.admittime > ca.dischtime -- Readmission must be AFTER discharge
              AND DATE_DIFF(next_adm.admittime, ca.dischtime, DAY) <= 30
          THEN 1
          ELSE 0
        END
      ) AS readmitted_30_day
    FROM
      cohort_admissions AS ca
    LEFT JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS next_adm
      ON ca.subject_id = next_adm.subject_id
      AND next_adm.admittime > ca.dischtime -- Subsequent admission must occur after discharge of the index admission
    GROUP BY
      ca.subject_id,
      ca.hadm_id,
      ca.admittime,
      ca.dischtime
  )
-- Step 6: Calculate the average 30-day readmission rate
SELECT
  AVG(rf.readmitted_30_day) AS average_30_day_readmission_rate
FROM
  readmissions_flagged AS rf;