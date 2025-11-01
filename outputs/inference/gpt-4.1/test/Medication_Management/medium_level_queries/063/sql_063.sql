WITH cohort AS (
  -- Select male patients aged 45-55 at admission with both diabetes and heart failure
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    -- Age filter: anchor_age is age at anchor_year, admittime is in anchor_year
    WHERE pat.gender = 'M'
      AND pat.anchor_age BETWEEN 45 AND 55
      AND adm.admittime >= DATETIME(CONCAT(CAST(pat.anchor_year AS STRING), '-01-01 00:00:00'))
      AND adm.admittime < DATETIME(CONCAT(CAST(pat.anchor_year + 1 AS STRING), '-01-01 00:00:00'))
      AND adm.hospital_expire_flag = 0 -- exclude in-hospital deaths
      AND adm.dischtime IS NOT NULL
      AND adm.admittime IS NOT NULL
      AND adm.dischtime > adm.admittime
      AND adm.hadm_id IN (
        -- Must have at least one diabetes and one heart failure code
        SELECT hadm_id
        FROM (
          SELECT
            hadm_id,
            MAX(CASE WHEN
              (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250')) OR
              (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E1[0-4]'))
              THEN 1 ELSE 0 END) AS has_diabetes,
            MAX(CASE WHEN
              (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^428')) OR
              (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50'))
              THEN 1 ELSE 0 END) AS has_hf
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
          GROUP BY hadm_id
        )
        WHERE has_diabetes = 1 AND has_hf = 1
      )
),
drug_initiation AS (
  -- For each admission, find first order time for insulin and oral antidiabetics
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    MIN(CASE WHEN LOWER(pres.drug) LIKE '%insulin%' THEN pres.starttime ELSE NULL END) AS insulin_start,
    MIN(CASE WHEN
      LOWER(pres.drug) LIKE '%metformin%' OR
      LOWER(pres.drug) LIKE '%glipizide%' OR
      LOWER(pres.drug) LIKE '%glyburide%' OR
      LOWER(pres.drug) LIKE '%glimepiride%' OR
      LOWER(pres.drug) LIKE '%pioglitazone%' OR
      LOWER(pres.drug) LIKE '%sitagliptin%' OR
      LOWER(pres.drug) LIKE '%linagliptin%' OR
      LOWER(pres.drug) LIKE '%canagliflozin%' OR
      LOWER(pres.drug) LIKE '%dapagliflozin%' OR
      LOWER(pres.drug) LIKE '%empagliflozin%' OR
      LOWER(pres.drug) LIKE '%repaglinide%' OR
      LOWER(pres.drug) LIKE '%nateglinide%' OR
      LOWER(pres.drug) LIKE '%acarbose%' OR
      LOWER(pres.drug) LIKE '%miglitol%' OR
      LOWER(pres.drug) LIKE '%rosiglitazone%' OR
      LOWER(pres.drug) LIKE '%tolbutamide%' OR
      LOWER(pres.drug) LIKE '%chlorpropamide%' OR
      LOWER(pres.drug) LIKE '%tolazamide%' OR
      LOWER(pres.drug) LIKE '%exenatide%' OR
      LOWER(pres.drug) LIKE '%liraglutide%' OR
      LOWER(pres.drug) LIKE '%semaglutide%'
      THEN pres.starttime ELSE NULL END) AS oral_start
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
      ON c.subject_id = pres.subject_id AND c.hadm_id = pres.hadm_id
      AND pres.starttime >= c.admittime AND pres.starttime < c.dischtime
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
),
initiation_flags AS (
  -- For each admission, flag if insulin/oral was initiated in first 12h or final 72h
  SELECT
    subject_id,
    hadm_id,
    -- Insulin initiation
    CASE WHEN insulin_start IS NOT NULL AND TIMESTAMP_DIFF(TIMESTAMP(insulin_start), TIMESTAMP(admittime), HOUR) <= 12 THEN 1 ELSE 0 END AS insulin_first12h,
    CASE WHEN insulin_start IS NOT NULL AND TIMESTAMP_DIFF(TIMESTAMP(dischtime), TIMESTAMP(insulin_start), HOUR) <= 72 THEN 1 ELSE 0 END AS insulin_final72h,
    -- Oral antidiabetic initiation
    CASE WHEN oral_start IS NOT NULL AND TIMESTAMP_DIFF(TIMESTAMP(oral_start), TIMESTAMP(admittime), HOUR) <= 12 THEN 1 ELSE 0 END AS oral_first12h,
    CASE WHEN oral_start IS NOT NULL AND TIMESTAMP_DIFF(TIMESTAMP(dischtime), TIMESTAMP(oral_start), HOUR) <= 72 THEN 1 ELSE 0 END AS oral_final72h
  FROM drug_initiation
)
SELECT
  -- Insulin
  ROUND(100 * SUM(insulin_first12h) / COUNT(*), 1) AS insulin_first12h_pct,
  ROUND(100 * SUM(insulin_final72h) / COUNT(*), 1) AS insulin_final72h_pct,
  ROUND(100 * (SUM(insulin_first12h) / COUNT(*) - SUM(insulin_final72h) / COUNT(*)), 1) AS insulin_pp_diff,
  -- Oral antidiabetics
  ROUND(100 * SUM(oral_first12h) / COUNT(*), 1) AS oral_first12h_pct,
  ROUND(100 * SUM(oral_final72h) / COUNT(*), 1) AS oral_final72h_pct,
  ROUND(100 * (SUM(oral_first12h) / COUNT(*) - SUM(oral_final72h) / COUNT(*)), 1) AS oral_pp_diff,
  COUNT(*) AS n_admissions
FROM initiation_flags;