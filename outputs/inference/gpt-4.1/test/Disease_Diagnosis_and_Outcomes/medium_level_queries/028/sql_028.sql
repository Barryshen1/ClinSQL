WITH
-- Step 1: Identify HF ICD codes (ICD-9: 428.x, ICD-10: I50.x)
hf_icd_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428'))
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
),

-- Step 2: Get male patients aged 43–53
target_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 43 AND 53
),

-- Step 3: Admissions with HF diagnosis
hf_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.deathtime, adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN target_patients pat ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN hf_icd_codes hf
    ON diag.icd_code = hf.icd_code AND diag.icd_version = hf.icd_version
  WHERE adm.admittime IS NOT NULL AND adm.dischtime IS NOT NULL
),

-- Step 4: Calculate LOS (in days)
hf_admissions_los AS (
  SELECT
    subject_id,
    hadm_id,
    hospital_expire_flag,
    DATETIME_DIFF(dischtime, admittime, DAY) AS los
  FROM hf_admissions
  WHERE DATETIME_DIFF(dischtime, admittime, DAY) >= 0
),

-- Step 5: Comorbidity burden (count unique non-HF diagnoses per admission)
comorbidity_counts AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    COUNT(DISTINCT CASE
      WHEN NOT (
        (diag.icd_version = 9 AND REGEXP_CONTAINS(diag.icd_code, r'^428'))
        OR (diag.icd_version = 10 AND REGEXP_CONTAINS(diag.icd_code, r'^I50'))
      )
      THEN diag.icd_code
      ELSE NULL
    END) AS comorbidity_count
  FROM hf_admissions adm
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  GROUP BY adm.subject_id, adm.hadm_id
),

-- Step 6: Merge LOS and comorbidity burden
hf_admissions_full AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los,
    a.hospital_expire_flag,
    c.comorbidity_count
  FROM hf_admissions_los a
  LEFT JOIN comorbidity_counts c
    ON a.subject_id = c.subject_id AND a.hadm_id = c.hadm_id
),

-- Step 7: Assign comorbidity burden category
hf_admissions_burden AS (
  SELECT *,
    CASE
      WHEN comorbidity_count <= 1 THEN 'Low'
      WHEN comorbidity_count BETWEEN 2 AND 3 THEN 'Medium'
      WHEN comorbidity_count >= 4 THEN 'High'
      ELSE 'Unknown'
    END AS comorbidity_burden
  FROM hf_admissions_full
),

-- Step 8: Calculate LOS quartiles for the cohort
los_quartiles AS (
  SELECT
    APPROX_QUANTILES(los, 4) AS los_quartiles
  FROM hf_admissions_burden
),

-- Step 9: Assign LOS quartile to each admission
hf_admissions_final AS (
  SELECT
    a.*,
    CASE
      WHEN a.los < q.los_quartiles[SAFE_OFFSET(1)] THEN 'Q1'
      WHEN a.los < q.los_quartiles[SAFE_OFFSET(2)] THEN 'Q2'
      WHEN a.los < q.los_quartiles[SAFE_OFFSET(3)] THEN 'Q3'
      ELSE 'Q4'
    END AS los_quartile
  FROM hf_admissions_burden a
  CROSS JOIN los_quartiles q
)

-- Step 10: Aggregate mortality by LOS quartile and comorbidity burden
SELECT
  los_quartile,
  comorbidity_burden,
  COUNT(*) AS n_admissions,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  ROUND(100 * SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS mortality_percent
FROM hf_admissions_final
WHERE comorbidity_burden IN ('Low', 'Medium', 'High')
GROUP BY los_quartile, comorbidity_burden
ORDER BY los_quartile, comorbidity_burden;