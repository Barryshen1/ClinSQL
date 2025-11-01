WITH cohort AS (
  -- Select male inpatients aged 49-59 with T2DM and heart failure
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- T2DM ICD-10 E11.*, ICD-9 250.x0, 250.x2
          (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'E11')
          OR (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '250'
              AND RIGHT(d.icd_code, 2) IN ('00','02','10','12','20','22','30','32','40','42','50','52','60','62','70','72','80','82','90','92'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- Heart Failure ICD-10 I50.*, ICD-9 428.*
          (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'I50')
          OR (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '428')
        )
    )
),

drug_classes AS (
  -- Drug class definitions for string matching
  SELECT 'Antidiabetic' AS drug_class, drug_name FROM UNNEST([
    'metformin','insulin','glipizide','glyburide','glimepiride','sitagliptin','linagliptin','empagliflozin','canagliflozin','dapagliflozin','pioglitazone','rosiglitazone','liraglutide','semaglutide'
  ]) AS drug_name
  UNION ALL
  SELECT 'Beta-Blocker', drug_name FROM UNNEST([
    'metoprolol','carvedilol','bisoprolol','atenolol','propranolol','labetalol'
  ]) AS drug_name
  UNION ALL
  SELECT 'ACEi/ARB/ARNI', drug_name FROM UNNEST([
    'lisinopril','enalapril','ramipril','captopril','benazepril','losartan','valsartan','candesartan','olmesartan','sacubitril','sacubitril/valsartan'
  ]) AS drug_name
  UNION ALL
  SELECT 'Loop Diuretic', drug_name FROM UNNEST([
    'furosemide','bumetanide','torsemide','ethacrynic acid'
  ]) AS drug_name
),

presc_exposure AS (
  -- For each admission, drug class, determine exposure in first 24h and final 48h
  SELECT
    c.subject_id,
    c.hadm_id,
    dc.drug_class,
    -- Exposed in first 24h
    MAX(
      CASE
        WHEN LOWER(pr.drug) LIKE CONCAT('%', LOWER(dc.drug_name), '%')
         AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
         AND pr.stoptime > c.admittime
        THEN 1 ELSE 0 END
    ) AS exposed_first24h,
    -- Exposed in final 48h
    MAX(
      CASE
        WHEN LOWER(pr.drug) LIKE CONCAT('%', LOWER(dc.drug_name), '%')
         AND pr.starttime < c.dischtime
         AND pr.stoptime > DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR)
        THEN 1 ELSE 0 END
    ) AS exposed_final48h
  FROM cohort c
  CROSS JOIN drug_classes dc
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON pr.hadm_id = c.hadm_id
  GROUP BY c.subject_id, c.hadm_id, dc.drug_class
),

admission_drug_status AS (
  -- For each admission and drug class, classify exposure status
  SELECT
    subject_id,
    hadm_id,
    drug_class,
    exposed_first24h,
    exposed_final48h,
    CASE
      WHEN exposed_first24h = 1 AND exposed_final48h = 1 THEN 'Continued'
      WHEN exposed_first24h = 0 AND exposed_final48h = 1 THEN 'Initiated'
      WHEN exposed_first24h = 1 AND exposed_final48h = 0 THEN 'Discontinued'
      ELSE NULL
    END AS exposure_status
  FROM presc_exposure
),

summary AS (
  -- Aggregate counts and percentages per drug class
  SELECT
    drug_class,
    COUNT(DISTINCT hadm_id) AS n_admissions,
    SUM(CASE WHEN exposed_first24h = 1 THEN 1 ELSE 0 END) AS n_first24h,
    SUM(CASE WHEN exposed_final48h = 1 THEN 1 ELSE 0 END) AS n_final48h,
    SUM(CASE WHEN exposure_status = 'Continued' THEN 1 ELSE 0 END) AS n_continued,
    SUM(CASE WHEN exposure_status = 'Initiated' THEN 1 ELSE 0 END) AS n_initiated,
    SUM(CASE WHEN exposure_status = 'Discontinued' THEN 1 ELSE 0 END) AS n_discontinued
  FROM admission_drug_status
  GROUP BY drug_class
)

SELECT
  drug_class,
  n_admissions,
  ROUND(100.0 * n_first24h / n_admissions, 1) AS pct_first24h,
  ROUND(100.0 * n_final48h / n_admissions, 1) AS pct_final48h,
  n_continued,
  n_initiated,
  n_discontinued
FROM summary
ORDER BY drug_class;