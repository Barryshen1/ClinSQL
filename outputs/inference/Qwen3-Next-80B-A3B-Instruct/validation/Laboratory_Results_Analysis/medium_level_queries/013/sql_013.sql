WITH first_hstnt AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY a.hadm_id ORDER BY le.charttime) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses did
    ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.labevents le
    ON a.hadm_id = le.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 50 AND 60
    AND le.charttime >= a.admittime
    AND (
      -- AMI ICD-9
      (di.icd_version = 9 AND di.icd_code LIKE '410%')
      OR
      -- AMI ICD-10
      (di.icd_version = 10 AND (di.icd_code LIKE 'I21%' OR di.icd_code LIKE 'I22%'))
      OR
      -- Chest pain ICD-9
      (di.icd_version = 9 AND di.icd_code IN ('786.50', '786.51', '786.59'))
      OR
      -- Chest pain ICD-10
      (di.icd_version = 10 AND di.icd_code LIKE 'R07%')
    )
    AND LOWER(dl.label) LIKE '%hs%t%'  -- hs-TnT
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0.014  -- above ULN
)
SELECT
  COUNT(DISTINCT subject_id) AS patient_count,
  COUNT(*) AS admission_count,
  AVG(valuenum) AS mean_hstnt,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_hstnt,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - APPROX_QUANTILES(valuenum, 100)[OFFSET(25)] AS iqr_hstnt
FROM
  first_hstnt
WHERE
  rn = 1;