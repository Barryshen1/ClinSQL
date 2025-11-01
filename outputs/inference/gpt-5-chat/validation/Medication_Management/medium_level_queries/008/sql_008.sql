WITH cohort AS (
  -- Female, 44-54 yo inpatients with BOTH T2DM and Heart Failure
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
        AND (
             (d.icd_version = 10 AND di.icd_code LIKE 'E11%')
             OR (d.icd_version = 9 AND di.icd_code LIKE '250%' AND RIGHT(d.icd_code,1) IN ('0','2'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.subject_id = a.subject_id AND d.hadm_id = a.hadm_id
        AND (
             (d.icd_version = 10 AND di.icd_code LIKE 'I50%')
             OR (d.icd_version = 9 AND di.icd_code LIKE '428%')
        )
    )
),
med_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    -- First 24h window
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%'
              AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
              AND COALESCE(pr.stoptime, c.dischtime) > c.admittime
             THEN 1 ELSE 0 END) AS insulin_first24h,
    MAX(CASE WHEN (
                  LOWER(pr.drug) LIKE '%metformin%'
               OR LOWER(pr.drug) LIKE '%glipizide%'
               OR LOWER(pr.drug) LIKE '%glyburide%'
               OR LOWER(pr.drug) LIKE '%glimepiride%'
               OR LOWER(pr.drug) LIKE '%sitagliptin%'
               OR LOWER(pr.drug) LIKE '%linagliptin%'
               OR LOWER(pr.drug) LIKE '%empagliflozin%'
               OR LOWER(pr.drug) LIKE '%dapagliflozin%'
               OR LOWER(pr.drug) LIKE '%pioglitazone%'
             )
              AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
              AND COALESCE(pr.stoptime, c.dischtime) > c.admittime
             THEN 1 ELSE 0 END) AS oha_first24h,
    -- Last 48h window
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%'
              AND pr.starttime < c.dischtime
              AND COALESCE(pr.stoptime, c.dischtime) > DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS insulin_last48h,
    MAX(CASE WHEN (
                  LOWER(pr.drug) LIKE '%metformin%'
               OR LOWER(pr.drug) LIKE '%glipizide%'
               OR LOWER(pr.drug) LIKE '%glyburide%'
               OR LOWER(pr.drug) LIKE '%glimepiride%'
               OR LOWER(pr.drug) LIKE '%sitagliptin%'
               OR LOWER(pr.drug) LIKE '%linagliptin%'
               OR LOWER(pr.drug) LIKE '%empagliflozin%'
               OR LOWER(pr.drug) LIKE '%dapagliflozin%'
               OR LOWER(pr.drug) LIKE '%pioglitazone%'
             )
              AND pr.starttime < c.dischtime
              AND COALESCE(pr.stoptime, c.dischtime) > DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR)
             THEN 1 ELSE 0 END) AS oha_last48h
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),
summary AS (
  SELECT
    COUNT(*) AS total_patients,
    -- Insulin
    SUM(insulin_first24h)/COUNT(*)*100 AS insulin_first24h_pct,
    SUM(insulin_last48h)/COUNT(*)*100 AS insulin_last48h_pct,
    SUM(CASE WHEN insulin_first24h=1 AND insulin_last48h=1 THEN 1 ELSE 0 END) AS insulin_continued,
    SUM(CASE WHEN insulin_first24h=0 AND insulin_last48h=1 THEN 1 ELSE 0 END) AS insulin_initiated,
    SUM(CASE WHEN insulin_first24h=1 AND insulin_last48h=0 THEN 1 ELSE 0 END) AS insulin_discontinued,
    -- Oral Hypoglycemic Agents (OHA)
    SUM(oha_first24h)/COUNT(*)*100 AS oha_first24h_pct,
    SUM(oha_last48h)/COUNT(*)*100 AS oha_last48h_pct,
    SUM(CASE WHEN oha_first24h=1 AND oha_last48h=1 THEN 1 ELSE 0 END) AS oha_continued,
    SUM(CASE WHEN oha_first24h=0 AND oha_last48h=1 THEN 1 ELSE 0 END) AS oha_initiated,
    SUM(CASE WHEN oha_first24h=1 AND oha_last48h=0 THEN 1 ELSE 0 END) AS oha_discontinued
  FROM med_flags
)
SELECT * FROM summary;