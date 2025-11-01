WITH cohort AS (
  -- Select male inpatients age 63-73 with both T2DM and HF
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 24
    AND a.hadm_id IN (
      -- Admissions with T2DM
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (
          (icd_version = 10 AND icd_code LIKE 'E11%')
          OR
          (icd_version = 9 AND icd_code LIKE '250%' AND RIGHT(icd_code,1) IN ('0','2'))
        )
    )
    AND a.hadm_id IN (
      -- Admissions with HF
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE
        (icd_version = 10 AND icd_code LIKE 'I50%')
        OR
        (icd_version = 9 AND icd_code LIKE '428%')
    )
),

meds AS (
  -- Medication administrations (insulin and oral agents) in first/final 24h
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- Insulin in first 24h
    MAX(
      CASE
        WHEN (
          (
            (LOWER(pr.drug) LIKE '%insulin%')
            OR (LOWER(em.medication) LIKE '%insulin%')
          )
          AND (
            (
              pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
            )
            OR (
              em.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
            )
          )
        )
        THEN 1 ELSE 0
      END
    ) AS insulin_first24,
    -- Insulin in final 24h
    MAX(
      CASE
        WHEN (
          (
            (LOWER(pr.drug) LIKE '%insulin%')
            OR (LOWER(em.medication) LIKE '%insulin%')
          )
          AND (
            (
              pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
            )
            OR (
              em.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
            )
          )
        )
        THEN 1 ELSE 0
      END
    ) AS insulin_final24,
    -- Oral agent in first 24h
    MAX(
      CASE
        WHEN (
          (
            (
              LOWER(pr.drug) LIKE '%metformin%'
              OR LOWER(pr.drug) LIKE '%glipizide%'
              OR LOWER(pr.drug) LIKE '%glyburide%'
              OR LOWER(pr.drug) LIKE '%glimepiride%'
              OR LOWER(pr.drug) LIKE '%sitagliptin%'
              OR LOWER(pr.drug) LIKE '%linagliptin%'
              OR LOWER(pr.drug) LIKE '%pioglitazone%'
              OR LOWER(pr.drug) LIKE '%empagliflozin%'
              OR LOWER(pr.drug) LIKE '%canagliflozin%'
              OR LOWER(pr.drug) LIKE '%dapagliflozin%'
              OR LOWER(pr.drug) LIKE '%repaglinide%'
              OR LOWER(pr.drug) LIKE '%nateglinide%'
              OR LOWER(pr.drug) LIKE '%acarbose%'
              OR LOWER(pr.drug) LIKE '%miglitol%'
              OR LOWER(pr.drug) LIKE '%rosiglitazone%'
              OR LOWER(pr.drug) LIKE '%tolbutamide%'
              OR LOWER(pr.drug) LIKE '%chlorpropamide%'
              OR LOWER(pr.drug) LIKE '%saxagliptin%'
              OR LOWER(pr.drug) LIKE '%alogliptin%'
            )
            OR
            (
              LOWER(em.medication) LIKE '%metformin%'
              OR LOWER(em.medication) LIKE '%glipizide%'
              OR LOWER(em.medication) LIKE '%glyburide%'
              OR LOWER(em.medication) LIKE '%glimepiride%'
              OR LOWER(em.medication) LIKE '%sitagliptin%'
              OR LOWER(em.medication) LIKE '%linagliptin%'
              OR LOWER(em.medication) LIKE '%pioglitazone%'
              OR LOWER(em.medication) LIKE '%empagliflozin%'
              OR LOWER(em.medication) LIKE '%canagliflozin%'
              OR LOWER(em.medication) LIKE '%dapagliflozin%'
              OR LOWER(em.medication) LIKE '%repaglinide%'
              OR LOWER(em.medication) LIKE '%nateglinide%'
              OR LOWER(em.medication) LIKE '%acarbose%'
              OR LOWER(em.medication) LIKE '%miglitol%'
              OR LOWER(em.medication) LIKE '%rosiglitazone%'
              OR LOWER(em.medication) LIKE '%tolbutamide%'
              OR LOWER(em.medication) LIKE '%chlorpropamide%'
              OR LOWER(em.medication) LIKE '%saxagliptin%'
              OR LOWER(em.medication) LIKE '%alogliptin%'
            )
          )
          AND (
            (
              pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
            )
            OR (
              em.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
            )
          )
        )
        THEN 1 ELSE 0
      END
    ) AS oral_first24,
    -- Oral agent in final 24h
    MAX(
      CASE
        WHEN (
          (
            (
              LOWER(pr.drug) LIKE '%metformin%'
              OR LOWER(pr.drug) LIKE '%glipizide%'
              OR LOWER(pr.drug) LIKE '%glyburide%'
              OR LOWER(pr.drug) LIKE '%glimepiride%'
              OR LOWER(pr.drug) LIKE '%sitagliptin%'
              OR LOWER(pr.drug) LIKE '%linagliptin%'
              OR LOWER(pr.drug) LIKE '%pioglitazone%'
              OR LOWER(pr.drug) LIKE '%empagliflozin%'
              OR LOWER(pr.drug) LIKE '%canagliflozin%'
              OR LOWER(pr.drug) LIKE '%dapagliflozin%'
              OR LOWER(pr.drug) LIKE '%repaglinide%'
              OR LOWER(pr.drug) LIKE '%nateglinide%'
              OR LOWER(pr.drug) LIKE '%acarbose%'
              OR LOWER(pr.drug) LIKE '%miglitol%'
              OR LOWER(pr.drug) LIKE '%rosiglitazone%'
              OR LOWER(pr.drug) LIKE '%tolbutamide%'
              OR LOWER(pr.drug) LIKE '%chlorpropamide%'
              OR LOWER(pr.drug) LIKE '%saxagliptin%'
              OR LOWER(pr.drug) LIKE '%alogliptin%'
            )
            OR
            (
              LOWER(em.medication) LIKE '%metformin%'
              OR LOWER(em.medication) LIKE '%glipizide%'
              OR LOWER(em.medication) LIKE '%glyburide%'
              OR LOWER(em.medication) LIKE '%glimepiride%'
              OR LOWER(em.medication) LIKE '%sitagliptin%'
              OR LOWER(em.medication) LIKE '%linagliptin%'
              OR LOWER(em.medication) LIKE '%pioglitazone%'
              OR LOWER(em.medication) LIKE '%empagliflozin%'
              OR LOWER(em.medication) LIKE '%canagliflozin%'
              OR LOWER(em.medication) LIKE '%dapagliflozin%'
              OR LOWER(em.medication) LIKE '%repaglinide%'
              OR LOWER(em.medication) LIKE '%nateglinide%'
              OR LOWER(em.medication) LIKE '%acarbose%'
              OR LOWER(em.medication) LIKE '%miglitol%'
              OR LOWER(em.medication) LIKE '%rosiglitazone%'
              OR LOWER(em.medication) LIKE '%tolbutamide%'
              OR LOWER(em.medication) LIKE '%chlorpropamide%'
              OR LOWER(em.medication) LIKE '%saxagliptin%'
              OR LOWER(em.medication) LIKE '%alogliptin%'
            )
          )
          AND (
            (
              pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
            )
            OR (
              em.charttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
            )
          )
        )
        THEN 1 ELSE 0
      END
    ) AS oral_final24
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
      ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` em
      ON c.subject_id = em.subject_id AND c.hadm_id = em.hadm_id
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime
),

agg AS (
  -- Aggregate prevalence
  SELECT
    COUNT(*) AS n_admissions,
    SUM(insulin_first24) AS n_insulin_first24,
    SUM(insulin_final24) AS n_insulin_final24,
    SUM(oral_first24) AS n_oral_first24,
    SUM(oral_final24) AS n_oral_final24
  FROM meds
)

SELECT
  n_admissions,
  ROUND(100.0 * n_insulin_first24 / n_admissions, 1) AS insulin_first24_pct,
  ROUND(100.0 * n_insulin_final24 / n_admissions, 1) AS insulin_final24_pct,
  ROUND(100.0 * (n_insulin_final24 - n_insulin_first24) / n_admissions, 1) AS insulin_net_change_pp,
  ROUND(100.0 * n_oral_first24 / n_admissions, 1) AS oral_first24_pct,
  ROUND(100.0 * n_oral_final24 / n_admissions, 1) AS oral_final24_pct,
  ROUND(100.0 * (n_oral_final24 - n_oral_first24) / n_admissions, 1) AS oral_net_change_pp
FROM agg;