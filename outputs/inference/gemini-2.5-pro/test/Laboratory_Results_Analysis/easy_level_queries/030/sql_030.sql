WITH acs_admissions AS (
  -- First, identify all hospital admissions for male patients with a diagnosis of Acute Coronary Syndrome (ACS)
  SELECT DISTINCT
    dx.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS dx
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON dx.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND
    -- Filter for ICD codes related to Acute Coronary Syndrome (ACS), which includes
    -- Myocardial Infarction (MI) and Unstable Angina across both ICD-9 and ICD-10 versions.
    -- Note: ICD codes in MIMIC do not contain periods.
    (
      (dx.icd_version = 9 AND (dx.icd_code LIKE '410%' OR dx.icd_code = '4111'))
      OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%' OR dx.icd_code = 'I200'))
    )
)
-- Now, find the minimum troponin value measured during these specific hospital admissions
SELECT
  MIN(le.valuenum) AS min_troponin
FROM
  `physionet-data.mimiciv_3_1_hosp.labevents` AS le
INNER JOIN
  acs_admissions AS adm
  ON le.hadm_id = adm.hadm_id
WHERE
  -- itemid 51003 is Troponin T, itemid 51002 is Troponin I
  le.itemid IN (51003, 51002)
  AND le.valuenum IS NOT NULL; -- Ensure the value is a number;