WITH cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 60 AND 70
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '250%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.subject_id = a.subject_id
        AND d2.hadm_id = a.hadm_id
        AND (
          (d2.icd_version = 10 AND d2.icd_code LIKE 'I50%')
          OR (d2.icd_version = 9 AND d2.icd_code LIKE '428%')
        )
    )
),
prescriptions_class AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    pr.starttime,
    CASE
      WHEN UPPER(pr.drug) LIKE '%INSULIN%'
        OR UPPER(pr.drug) LIKE '%METFORMIN%'
        OR UPPER(pr.drug) LIKE '%GLIPIZIDE%'
        OR UPPER(pr.drug) LIKE '%GLYBURIDE%'
        OR UPPER(pr.drug) LIKE '%GLIMEPIRIDE%'
        OR UPPER(pr.drug) LIKE '%PIOGLITAZONE%'
        OR UPPER(pr.drug) LIKE '%SITAGLIPTIN%'
        OR UPPER(pr.drug) LIKE '%EMPAGLIFLOZIN%'
        OR UPPER(pr.drug) LIKE '%LIRAGLUTIDE%'
        OR UPPER(pr.drug) LIKE '%SEMAGLUTIDE%'
      THEN 'antidiabetics'
      WHEN UPPER(pr.drug) LIKE '%METOPROLOL%'
        OR UPPER(pr.drug) LIKE '%ATENOLOL%'
        OR UPPER(pr.drug) LIKE '%CARVEDILOL%'
        OR UPPER(pr.drug) LIKE '%BISOPROLOL%'
        OR UPPER(pr.drug) LIKE '%PROPRANOLOL%'
      THEN 'beta_blockers'
      WHEN UPPER(pr.drug) LIKE '%LISINOPRIL%'
        OR UPPER(pr.drug) LIKE '%ENALAPRIL%'
        OR UPPER(pr.drug) LIKE '%RAMIPRIL%'
        OR UPPER(pr.drug) LIKE '%CAPTOPRIL%'
        OR UPPER(pr.drug) LIKE '%LOSARTAN%'
        OR UPPER(pr.drug) LIKE '%VALSARTAN%'
        OR UPPER(pr.drug) LIKE '%IRBESARTAN%'
        OR UPPER(pr.drug) LIKE '%CANDESARTAN%'
        OR UPPER(pr.drug) LIKE '%SACUBITRIL%'
      THEN 'ACEi_ARB_ARNI'
      WHEN UPPER(pr.drug) LIKE '%FUROSEMIDE%'
        OR UPPER(pr.drug) LIKE '%BUMETANIDE%'
        OR UPPER(pr.drug) LIKE '%TORSEMIDE%'
      THEN 'loop_diuretics'
      ELSE NULL
    END AS drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.hadm_id = c.hadm_id
  WHERE pr.starttime >= c.admittime
    AND pr.starttime < c.dischtime
    AND (
      UPPER(pr.drug) LIKE '%INSULIN%' OR UPPER(pr.drug) LIKE '%METFORMIN%' OR UPPER(pr.drug) LIKE '%GLIPIZIDE%' OR
      UPPER(pr.drug) LIKE '%GLYBURIDE%' OR UPPER(pr.drug) LIKE '%GLIMEPIRIDE%' OR UPPER(pr.drug) LIKE '%PIOGLITAZONE%' OR
      UPPER(pr.drug) LIKE '%SITAGLIPTIN%' OR UPPER(pr.drug) LIKE '%EMPAGLIFLOZIN%' OR UPPER(pr.drug) LIKE '%LIRAGLUTIDE%' OR
      UPPER(pr.drug) LIKE '%SEMAGLUTIDE%' OR UPPER(pr.drug) LIKE '%METOPROLOL%' OR UPPER(pr.drug) LIKE '%ATENOLOL%' OR
      UPPER(pr.drug) LIKE '%CARVEDILOL%' OR UPPER(pr.drug) LIKE '%BISOPROLOL%' OR UPPER(pr.drug) LIKE '%PROPRANOLOL%' OR
      UPPER(pr.drug) LIKE '%LISINOPRIL%' OR UPPER(pr.drug) LIKE '%ENALAPRIL%' OR UPPER(pr.drug) LIKE '%RAMIPRIL%' OR
      UPPER(pr.drug) LIKE '%CAPTOPRIL%' OR UPPER(pr.drug) LIKE '%LOSARTAN%' OR UPPER(pr.drug) LIKE '%VALSARTAN%' OR
      UPPER(pr.drug) LIKE '%IRBESARTAN%' OR UPPER(pr.drug) LIKE '%CANDESARTAN%' OR UPPER(pr.drug) LIKE '%SACUBITRIL%' OR
      UPPER(pr.drug) LIKE '%FUROSEMIDE%' OR UPPER(pr.drug) LIKE '%BUMETANIDE%' OR UPPER(pr.drug) LIKE '%TORSEMIDE%'
    )
),
min_start_per_class AS (
  SELECT
    hadm_id,
    drug_class,
    MIN(starttime) AS min_start
  FROM prescriptions_class
  WHERE drug_class IS NOT NULL
  GROUP BY hadm_id, drug_class
),
first48 AS (
  SELECT
    drug_class,
    COUNT(*) AS count_first
  FROM min_start_per_class m
  INNER JOIN cohort c
    ON m.hadm_id = c.hadm_id
  WHERE m.min_start >= c.admittime
    AND m.min_start < c.admittime + INTERVAL 2 DAY
  GROUP BY drug_class
),
last24 AS (
  SELECT
    drug_class,
    COUNT(*) AS count_last
  FROM min_start_per_class m
  INNER JOIN cohort c
    ON m.hadm_id = c.hadm_id
  WHERE m.min_start >= c.dischtime - INTERVAL 1 DAY
    AND m.min_start < c.dischtime
  GROUP BY drug_class
),
total_patients AS (
  SELECT COUNT(*) AS total
  FROM cohort
),
combined AS (
  SELECT
    COALESCE(f.drug_class, l.drug_class) AS drug_class,
    COALESCE(f.count_first, 0) AS count_first,
    COALESCE(l.count_last, 0) AS count_last
  FROM first48 f
  FULL OUTER JOIN last24 l
    ON f.drug_class = l.drug_class
)
SELECT
  drug_class,
  ROUND(count_first * 100.0 / total, 2) AS initiation_pct_first48,
  ROUND(count_last * 100.0 / total, 2) AS initiation_pct_last24,
  ROUND(ABS(count_first - count_last) * 100.0 / total, 2) AS abs_diff_pp
FROM combined
CROSS JOIN total_patients
ORDER BY drug_class;