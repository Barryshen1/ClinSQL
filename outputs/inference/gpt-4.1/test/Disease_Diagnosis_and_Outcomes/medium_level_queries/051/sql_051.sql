WITH cohort AS (
  -- Step 1: Select men aged 51–61 with postoperative complications
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 51 AND 61
    AND (
      -- ICD-10 postoperative complications
      (dx.icd_version = 10 AND (
        LEFT(dx.icd_code, 3) IN ('T81', 'T82', 'T83', 'T84', 'T85')
      ))
      -- ICD-9 postoperative complications
      OR (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) = '998')
    )
),
icu_status AS (
  -- Step 2: Determine ICU status per admission
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.gender,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    CASE WHEN icu.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
      ON c.hadm_id = icu.hadm_id
),
los_bins AS (
  -- Step 3: Calculate LOS and bin
  SELECT
    *,
    SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) AS los_days,
    CASE
      WHEN SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) BETWEEN 1 AND 2 THEN '1-2'
      WHEN SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) BETWEEN 3 AND 5 THEN '3-5'
      WHEN SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) BETWEEN 6 AND 9 THEN '6-9'
      WHEN SAFE_CAST(TIMESTAMP_DIFF(dischtime, admittime, DAY) AS INT64) >= 10 THEN '>=10'
      ELSE NULL
    END AS los_bin
  FROM
    icu_status
),
charlson_components AS (
  -- Step 4: Identify Charlson comorbidities per admission
  SELECT
    dx.hadm_id,
    MAX(CASE
      -- Myocardial infarction
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) = 'I21') OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) = '410') THEN 1 ELSE 0 END) AS mi,
    MAX(CASE
      -- Congestive heart failure
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('I50')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('428')) THEN 1 ELSE 0 END) AS chf,
    MAX(CASE
      -- Peripheral vascular disease
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('I73')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('443')) THEN 1 ELSE 0 END) AS pvd,
    MAX(CASE
      -- Cerebrovascular disease
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('I63', 'I64')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('433', '434', '436')) THEN 1 ELSE 0 END) AS cerebro,
    MAX(CASE
      -- Dementia
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('F03')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('290')) THEN 1 ELSE 0 END) AS dementia,
    MAX(CASE
      -- Chronic pulmonary disease
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('J44')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('496')) THEN 1 ELSE 0 END) AS copd,
    MAX(CASE
      -- Rheumatic disease
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('M06')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('714')) THEN 1 ELSE 0 END) AS rheum,
    MAX(CASE
      -- Peptic ulcer disease
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('K25')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('531')) THEN 1 ELSE 0 END) AS pud,
    MAX(CASE
      -- Mild liver disease
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('K73', 'K74')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('571')) THEN 1 ELSE 0 END) AS mild_liver,
    MAX(CASE
      -- Diabetes (without complication)
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('E10', 'E11', 'E13', 'E14')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) = '250') THEN 1 ELSE 0 END) AS diabetes,
    MAX(CASE
      -- Diabetes (with complication)
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('E102', 'E112', 'E132', 'E142')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 5) IN ('25040', '25041', '25042', '25043')) THEN 1 ELSE 0 END) AS diabetes_comp,
    MAX(CASE
      -- CKD
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) = 'N18') OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) = '585') THEN 1 ELSE 0 END) AS ckd,
    MAX(CASE
      -- Hemiplegia
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('G81')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('342')) THEN 1 ELSE 0 END) AS hemiplegia,
    MAX(CASE
      -- Malignancy
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('C00', 'C01', 'C02', 'C03', 'C04', 'C05', 'C06', 'C07', 'C08', 'C09', 'C10', 'C11', 'C12', 'C13', 'C14', 'C15', 'C16', 'C17', 'C18', 'C19', 'C20', 'C21', 'C22', 'C23', 'C24', 'C25', 'C26', 'C30', 'C31', 'C32', 'C33', 'C34', 'C37', 'C38', 'C39', 'C40', 'C41', 'C43', 'C45', 'C46', 'C47', 'C48', 'C49', 'C50', 'C51', 'C52', 'C53', 'C54', 'C55', 'C56', 'C57', 'C58', 'C60', 'C61', 'C62', 'C63', 'C64', 'C65', 'C66', 'C67', 'C68', 'C69', 'C70', 'C71', 'C72', 'C73', 'C74', 'C75', 'C76', 'C80', 'C81', 'C82', 'C83', 'C84', 'C85', 'C88', 'C90', 'C91', 'C92', 'C93', 'C94', 'C95', 'C96')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('140', '141', '142', '143', '144', '145', '146', '147', '148', '149', '150', '151', '152', '153', '154', '155', '156', '157', '158', '159', '160', '161', '162', '163', '164', '165', '170', '171', '172', '174', '175', '176', '179', '180', '181', '182', '183', '184', '185', '186', '187', '188', '189', '190', '191', '192', '193', '194', '195', '196', '197', '198', '199')) THEN 1 ELSE 0 END) AS malignancy,
    MAX(CASE
      -- Moderate/severe liver disease
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('K72')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('572')) THEN 1 ELSE 0 END) AS severe_liver,
    MAX(CASE
      -- Metastatic solid tumor
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('C77', 'C78', 'C79', 'C80')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('196', '197', '198', '199')) THEN 1 ELSE 0 END) AS metastatic,
    MAX(CASE
      -- AIDS/HIV
      WHEN (dx.icd_version = 10 AND LEFT(dx.icd_code, 3) IN ('B20')) OR
           (dx.icd_version = 9 AND LEFT(dx.icd_code, 3) IN ('042')) THEN 1 ELSE 0 END) AS aids
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
  GROUP BY
    dx.hadm_id
),
charlson_score AS (
  -- Step 4b: Calculate Charlson index per admission
  SELECT
    hadm_id,
    -- Assign weights per Charlson definition
    (
      mi +
      chf +
      pvd +
      cerebro +
      dementia +
      copd +
      rheum +
      pud +
      mild_liver +
      CASE WHEN diabetes = 1 OR diabetes_comp = 1 THEN 1 ELSE 0 END +
      ckd +
      hemiplegia * 2 +
      malignancy * 2 +
      severe_liver * 3 +
      metastatic * 6 +
      aids * 6
    ) AS charlson_index,
    ckd,
    CASE WHEN diabetes = 1 OR diabetes_comp = 1 THEN 1 ELSE 0 END AS diabetes
  FROM
    charlson_components
),
final_cohort AS (
  -- Step 5: Merge all info
  SELECT
    l.subject_id,
    l.hadm_id,
    l.anchor_age,
    l.gender,
    l.admittime,
    l.dischtime,
    l.hospital_expire_flag,
    l.icu_status,
    l.los_days,
    l.los_bin,
    COALESCE(cs.charlson_index, 0) AS charlson_index,
    COALESCE(cs.ckd, 0) AS ckd,
    COALESCE(cs.diabetes, 0) AS diabetes,
    CASE
      WHEN COALESCE(cs.charlson_index, 0) BETWEEN 0 AND 1 THEN '0-1'
      WHEN COALESCE(cs.charlson_index, 0) = 2 THEN '2'
      WHEN COALESCE(cs.charlson_index, 0) >= 3 THEN '>=3'
      ELSE NULL
    END AS charlson_bin
  FROM
    los_bins l
    LEFT JOIN charlson_score cs
      ON l.hadm_id = cs.hadm_id
  WHERE
    l.los_bin IS NOT NULL
    AND charlson_bin IS NOT NULL
)
-- Step 6: Aggregate and report
SELECT
  icu_status,
  los_bin,
  charlson_bin,
  COUNT(*) AS n_admissions,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS mortality_percent,
  APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
  ROUND(SUM(CASE WHEN ckd = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS ckd_percent,
  ROUND(SUM(CASE WHEN diabetes = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS diabetes_percent
FROM
  final_cohort
GROUP BY
  icu_status, los_bin, charlson_bin
ORDER BY
  icu_status, los_bin, charlson_bin;