WITH cohort AS (
  -- Select male patients age 68-78
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
diabetes_hadm AS (
  -- Admissions with diabetes diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (
      (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250'))
      OR
      (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E1[0-4]'))
    )
),
hf_hadm AS (
  -- Admissions with acute heart failure diagnosis
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (
      (icd_version = 9 AND (
        icd_code IN ('4280','42821','42823','42831','42833','42841','42843','4289')
        OR REGEXP_CONTAINS(icd_code, r'^428')
      ))
      OR
      (icd_version = 10 AND (
        REGEXP_CONTAINS(icd_code, r'^I50')
        OR icd_code IN ('I5021','I5023','I5031','I5033','I5041','I5043','I509')
      ))
    )
),
final_cohort AS (
  -- Admissions with both diabetes and acute HF
  SELECT c.*
  FROM cohort c
  JOIN diabetes_hadm d ON c.hadm_id = d.hadm_id
  JOIN hf_hadm h ON c.hadm_id = h.hadm_id
),
med_initiation AS (
  -- Find first insulin and oral agent initiation per hadm_id
  SELECT
    fc.hadm_id,
    fc.subject_id,
    fc.admittime,
    fc.dischtime,

    -- Insulin initiation times
    MIN(
      CASE
        WHEN LOWER(pr.drug) LIKE '%insulin%' THEN CAST(pr.starttime AS TIMESTAMP)
        ELSE NULL
      END
    ) AS insulin_rx_time,
    MIN(
      CASE
        WHEN LOWER(em.medication) LIKE '%insulin%' THEN CAST(em.charttime AS TIMESTAMP)
        ELSE NULL
      END
    ) AS insulin_emar_time,
    MIN(
      CASE
        WHEN LOWER(ie.ordercategorydescription) LIKE '%insulin%' THEN CAST(ie.starttime AS TIMESTAMP)
        ELSE NULL
      END
    ) AS insulin_icu_time,

    -- Oral agent initiation times (common oral diabetes drugs)
    MIN(
      CASE
        WHEN LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' OR LOWER(pr.drug) LIKE '%repaglinide%' OR LOWER(pr.drug) LIKE '%nateglinide%' OR LOWER(pr.drug) LIKE '%acarbose%' OR LOWER(pr.drug) LIKE '%miglitol%' THEN CAST(pr.starttime AS TIMESTAMP)
        ELSE NULL
      END
    ) AS oral_rx_time,
    MIN(
      CASE
        WHEN LOWER(em.medication) LIKE '%metformin%' OR LOWER(em.medication) LIKE '%glipizide%' OR LOWER(em.medication) LIKE '%glyburide%' OR LOWER(em.medication) LIKE '%glimepiride%' OR LOWER(em.medication) LIKE '%sitagliptin%' OR LOWER(em.medication) LIKE '%linagliptin%' OR LOWER(em.medication) LIKE '%canagliflozin%' OR LOWER(em.medication) LIKE '%dapagliflozin%' OR LOWER(em.medication) LIKE '%empagliflozin%' OR LOWER(em.medication) LIKE '%pioglitazone%' OR LOWER(em.medication) LIKE '%rosiglitazone%' OR LOWER(em.medication) LIKE '%repaglinide%' OR LOWER(em.medication) LIKE '%nateglinide%' OR LOWER(em.medication) LIKE '%acarbose%' OR LOWER(em.medication) LIKE '%miglitol%' THEN CAST(em.charttime AS TIMESTAMP)
        ELSE NULL
      END
    ) AS oral_emar_time
  FROM final_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON fc.hadm_id = pr.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` em
    ON fc.hadm_id = em.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON fc.hadm_id = ie.hadm_id
  GROUP BY fc.hadm_id, fc.subject_id, fc.admittime, fc.dischtime
),
init_window AS (
  -- For each admission, determine if insulin/oral agent was initiated in first/final 24h
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,

    -- Earliest insulin initiation time
    LEAST(insulin_rx_time, insulin_emar_time, insulin_icu_time) AS insulin_init_time,
    -- Earliest oral agent initiation time
    LEAST(oral_rx_time, oral_emar_time) AS oral_init_time,

    -- Flags for initiation in first/final 24h
    CASE
      WHEN LEAST(insulin_rx_time, insulin_emar_time, insulin_icu_time) IS NOT NULL
        AND LEAST(insulin_rx_time, insulin_emar_time, insulin_icu_time) >= CAST(admittime AS TIMESTAMP)
        AND LEAST(insulin_rx_time, insulin_emar_time, insulin_icu_time) < TIMESTAMP_ADD(CAST(admittime AS TIMESTAMP), INTERVAL 24 HOUR)
      THEN 1 ELSE 0 END AS insulin_first24h,
    CASE
      WHEN LEAST(insulin_rx_time, insulin_emar_time, insulin_icu_time) IS NOT NULL
        AND LEAST(insulin_rx_time, insulin_emar_time, insulin_icu_time) >= TIMESTAMP_SUB(CAST(dischtime AS TIMESTAMP), INTERVAL 24 HOUR)
        AND LEAST(insulin_rx_time, insulin_emar_time, insulin_icu_time) < CAST(dischtime AS TIMESTAMP)
      THEN 1 ELSE 0 END AS insulin_final24h,

    CASE
      WHEN LEAST(oral_rx_time, oral_emar_time) IS NOT NULL
        AND LEAST(oral_rx_time, oral_emar_time) >= CAST(admittime AS TIMESTAMP)
        AND LEAST(oral_rx_time, oral_emar_time) < TIMESTAMP_ADD(CAST(admittime AS TIMESTAMP), INTERVAL 24 HOUR)
      THEN 1 ELSE 0 END AS oral_first24h,
    CASE
      WHEN LEAST(oral_rx_time, oral_emar_time) IS NOT NULL
        AND LEAST(oral_rx_time, oral_emar_time) >= TIMESTAMP_SUB(CAST(dischtime AS TIMESTAMP), INTERVAL 24 HOUR)
        AND LEAST(oral_rx_time, oral_emar_time) < CAST(dischtime AS TIMESTAMP)
      THEN 1 ELSE 0 END AS oral_final24h
  FROM med_initiation
)
SELECT
  COUNT(*) AS n_admissions,
  ROUND(SUM(insulin_first24h) / COUNT(*) * 100, 1) AS insulin_first24h_rate_pct,
  ROUND(SUM(oral_first24h) / COUNT(*) * 100, 1) AS oral_first24h_rate_pct,
  ROUND(SUM(insulin_final24h) / COUNT(*) * 100, 1) AS insulin_final24h_rate_pct,
  ROUND(SUM(oral_final24h) / COUNT(*) * 100, 1) AS oral_final24h_rate_pct,
  ROUND(ABS(SUM(insulin_first24h) / COUNT(*) * 100 - SUM(oral_first24h) / COUNT(*) * 100), 1) AS abs_diff_first24h_pct,
  ROUND(ABS(SUM(insulin_final24h) / COUNT(*) * 100 - SUM(oral_final24h) / COUNT(*) * 100), 1) AS abs_diff_final24h_pct
FROM init_window;