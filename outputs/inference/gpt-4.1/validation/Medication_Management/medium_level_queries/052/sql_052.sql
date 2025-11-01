WITH cohort AS (
  -- Select 45-55yo male inpatients with T2DM and HF, LOS >= 48h
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.patients p
    INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
      ON p.subject_id = a.subject_id
    -- Age and gender filter
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 45 AND 55
      AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
      AND a.hospital_expire_flag = 0 -- exclude in-hospital deaths (optional)
      AND EXISTS (
        -- T2DM diagnosis
        SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
        WHERE d.hadm_id = a.hadm_id
          AND (
            -- ICD-10 E11.* or ICD-9 250.x0/250.x2
            (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
            OR (d.icd_version = 9 AND (
              d.icd_code LIKE '250%0' OR d.icd_code LIKE '250%2'
            ))
          )
      )
      AND EXISTS (
        -- Heart failure diagnosis
        SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
        WHERE d.hadm_id = a.hadm_id
          AND (
            (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
            OR (d.icd_version = 9 AND d.icd_code LIKE '428%')
          )
      )
),
meds AS (
  -- Gather all medication administrations/orders in first 48h and final 24h
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- First 48h window
    CASE
      WHEN (
        EXISTS (
          SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.prescriptions pr
          WHERE pr.hadm_id = c.hadm_id
            AND LOWER(pr.drug) LIKE '%insulin%'
            AND pr.starttime >= c.admittime
            AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
        )
        OR EXISTS (
          SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.emar em
          WHERE em.hadm_id = c.hadm_id
            AND LOWER(em.medication) LIKE '%insulin%'
            AND em.charttime >= c.admittime
            AND em.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
        )
      ) THEN 1 ELSE 0
    END AS insulin_48h,
    CASE
      WHEN (
        EXISTS (
          SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.prescriptions pr
          WHERE pr.hadm_id = c.hadm_id
            AND (
              LOWER(pr.drug) LIKE '%metformin%'
              OR LOWER(pr.drug) LIKE '%glipizide%'
              OR LOWER(pr.drug) LIKE '%glyburide%'
              OR LOWER(pr.drug) LIKE '%glimepiride%'
              OR LOWER(pr.drug) LIKE '%sitagliptin%'
              OR LOWER(pr.drug) LIKE '%linagliptin%'
              OR LOWER(pr.drug) LIKE '%pioglitazone%'
              OR LOWER(pr.drug) LIKE '%rosiglitazone%'
              OR LOWER(pr.drug) LIKE '%repaglinide%'
              OR LOWER(pr.drug) LIKE '%nateglinide%'
              OR LOWER(pr.drug) LIKE '%canagliflozin%'
              OR LOWER(pr.drug) LIKE '%dapagliflozin%'
              OR LOWER(pr.drug) LIKE '%empagliflozin%'
              OR LOWER(pr.drug) LIKE '%saxagliptin%'
              OR LOWER(pr.drug) LIKE '%alogliptin%'
              OR LOWER(pr.drug) LIKE '%exenatide%'
              OR LOWER(pr.drug) LIKE '%liraglutide%'
              OR LOWER(pr.drug) LIKE '%semaglutide%'
            )
            AND pr.starttime >= c.admittime
            AND pr.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
        )
        OR EXISTS (
          SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.emar em
          WHERE em.hadm_id = c.hadm_id
            AND (
              LOWER(em.medication) LIKE '%metformin%'
              OR LOWER(em.medication) LIKE '%glipizide%'
              OR LOWER(em.medication) LIKE '%glyburide%'
              OR LOWER(em.medication) LIKE '%glimepiride%'
              OR LOWER(em.medication) LIKE '%sitagliptin%'
              OR LOWER(em.medication) LIKE '%linagliptin%'
              OR LOWER(em.medication) LIKE '%pioglitazone%'
              OR LOWER(em.medication) LIKE '%rosiglitazone%'
              OR LOWER(em.medication) LIKE '%repaglinide%'
              OR LOWER(em.medication) LIKE '%nateglinide%'
              OR LOWER(em.medication) LIKE '%canagliflozin%'
              OR LOWER(em.medication) LIKE '%dapagliflozin%'
              OR LOWER(em.medication) LIKE '%empagliflozin%'
              OR LOWER(em.medication) LIKE '%saxagliptin%'
              OR LOWER(em.medication) LIKE '%alogliptin%'
              OR LOWER(em.medication) LIKE '%exenatide%'
              OR LOWER(em.medication) LIKE '%liraglutide%'
              OR LOWER(em.medication) LIKE '%semaglutide%'
            )
            AND em.charttime >= c.admittime
            AND em.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
        )
      ) THEN 1 ELSE 0
    END AS oral_48h,
    -- Final 24h window
    CASE
      WHEN (
        EXISTS (
          SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.prescriptions pr
          WHERE pr.hadm_id = c.hadm_id
            AND LOWER(pr.drug) LIKE '%insulin%'
            AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
            AND pr.starttime < c.dischtime
        )
        OR EXISTS (
          SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.emar em
          WHERE em.hadm_id = c.hadm_id
            AND LOWER(em.medication) LIKE '%insulin%'
            AND em.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
            AND em.charttime < c.dischtime
        )
      ) THEN 1 ELSE 0
    END AS insulin_24h,
    CASE
      WHEN (
        EXISTS (
          SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.prescriptions pr
          WHERE pr.hadm_id = c.hadm_id
            AND (
              LOWER(pr.drug) LIKE '%metformin%'
              OR LOWER(pr.drug) LIKE '%glipizide%'
              OR LOWER(pr.drug) LIKE '%glyburide%'
              OR LOWER(pr.drug) LIKE '%glimepiride%'
              OR LOWER(pr.drug) LIKE '%sitagliptin%'
              OR LOWER(pr.drug) LIKE '%linagliptin%'
              OR LOWER(pr.drug) LIKE '%pioglitazone%'
              OR LOWER(pr.drug) LIKE '%rosiglitazone%'
              OR LOWER(pr.drug) LIKE '%repaglinide%'
              OR LOWER(pr.drug) LIKE '%nateglinide%'
              OR LOWER(pr.drug) LIKE '%canagliflozin%'
              OR LOWER(pr.drug) LIKE '%dapagliflozin%'
              OR LOWER(pr.drug) LIKE '%empagliflozin%'
              OR LOWER(pr.drug) LIKE '%saxagliptin%'
              OR LOWER(pr.drug) LIKE '%alogliptin%'
              OR LOWER(pr.drug) LIKE '%exenatide%'
              OR LOWER(pr.drug) LIKE '%liraglutide%'
              OR LOWER(pr.drug) LIKE '%semaglutide%'
            )
            AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
            AND pr.starttime < c.dischtime
        )
        OR EXISTS (
          SELECT 1 FROM physionet-data.mimiciv_3_1_hosp.emar em
          WHERE em.hadm_id = c.hadm_id
            AND (
              LOWER(em.medication) LIKE '%metformin%'
              OR LOWER(em.medication) LIKE '%glipizide%'
              OR LOWER(em.medication) LIKE '%glyburide%'
              OR LOWER(em.medication) LIKE '%glimepiride%'
              OR LOWER(em.medication) LIKE '%sitagliptin%'
              OR LOWER(em.medication) LIKE '%linagliptin%'
              OR LOWER(em.medication) LIKE '%pioglitazone%'
              OR LOWER(em.medication) LIKE '%rosiglitazone%'
              OR LOWER(em.medication) LIKE '%repaglinide%'
              OR LOWER(em.medication) LIKE '%nateglinide%'
              OR LOWER(em.medication) LIKE '%canagliflozin%'
              OR LOWER(em.medication) LIKE '%dapagliflozin%'
              OR LOWER(em.medication) LIKE '%empagliflozin%'
              OR LOWER(em.medication) LIKE '%saxagliptin%'
              OR LOWER(em.medication) LIKE '%alogliptin%'
              OR LOWER(em.medication) LIKE '%exenatide%'
              OR LOWER(em.medication) LIKE '%liraglutide%'
              OR LOWER(em.medication) LIKE '%semaglutide%'
            )
            AND em.charttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR)
            AND em.charttime < c.dischtime
        )
      ) THEN 1 ELSE 0
    END AS oral_24h
  FROM cohort c
)
SELECT
  COUNT(*) AS n_patients,
  ROUND(SUM(insulin_48h) / COUNT(*) * 100, 1) AS pct_insulin_48h,
  ROUND(SUM(oral_48h) / COUNT(*) * 100, 1) AS pct_oral_48h,
  ROUND(SUM(insulin_24h) / COUNT(*) * 100, 1) AS pct_insulin_24h,
  ROUND(SUM(oral_24h) / COUNT(*) * 100, 1) AS pct_oral_24h
FROM meds;