WITH stroke_patients AS (
  -- Identify female patients aged 35-45 with stroke diagnoses
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 35 AND 45
    AND (
      -- Common stroke ICD-10 codes (adjust as needed)
      (d.icd_version = 10 AND d.icd_code LIKE 'I63.%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I61.%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I60.%') OR
      -- Common stroke ICD-9 codes (adjust as needed)
      (d.icd_version = 9 AND d.icd_code LIKE '434.%') OR
      (d.icd_version = 9 AND d.icd_code LIKE '436.%')
    )
),

icu_stays AS (
  -- Get ICU stays for these patients
  SELECT
    i.stay_id,
    i.los
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN
    stroke_patients sp
    ON i.subject_id = sp.subject_id AND i.hadm_id = sp.hadm_id
)

-- Calculate median ICU LOS
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_icu_los
FROM
  icu_stays;