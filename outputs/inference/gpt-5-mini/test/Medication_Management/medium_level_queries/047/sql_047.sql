WITH class_patterns AS (
  SELECT 'Antidiabetic' AS drug_class,
         '(metformin|insulin|glipizide|glyburide|glimepiride|sitagliptin|saxagliptin|linagliptin|alogliptin|liraglutide|semaglutide|exenatide|empagliflozin|dapagliflozin|canagliflozin|pioglitazone|rosiglitazone|acarbose|repaglinide|nateglinide)' AS pattern
  UNION ALL
  SELECT 'Beta-blocker', '(metoprolol|atenolol|propranolol|carvedilol|bisoprolol|nebivolol|nadolol|pindolol|timolol)'
  UNION ALL
  SELECT 'ACEi/ARB/ARNI', '(lisinopril|enalapril|ramipril|benazepril|quinapril|perindopril|fosinopril|trandolapril|captopril|losartan|valsartan|candesartan|irbesartan|olmesartan|telmisartan|sacubitril|entresto)'
  UNION ALL
  SELECT 'Loop diuretic', '(furosemide|bumetanide|torsemide|ethacrynic)'
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 40 AND 50
    -- require diabetes diagnosis on this admission (ICD label contains 'diabetes')
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%diabetes%'
    )
    -- require heart failure diagnosis on this admission (ICD label contains 'heart failure')
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code
        AND d.icd_version = dd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dd.long_title) LIKE '%heart failure%'
    )
),
-- Aggregate prescriptions per hadm_id and drug class to get binary flags for first/last 24h windows
presc_flags AS (
  SELECT
    c.hadm_id,
    cp.drug_class,
    MAX(CASE
          WHEN p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
               AND (p.stoptime IS NULL OR p.stoptime > c.admittime)
          THEN 1 ELSE 0 END) AS in_first,
    MAX(CASE
          WHEN p.starttime < c.dischtime
               AND (p.stoptime IS NULL OR p.stoptime > TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR))
          THEN 1 ELSE 0 END) AS in_last
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
      ON p.hadm_id = c.hadm_id
      AND p.starttime IS NOT NULL
    JOIN class_patterns cp
      ON REGEXP_CONTAINS(LOWER(COALESCE(p.drug, '')), cp.pattern)
  GROUP BY
    c.hadm_id, cp.drug_class
),
-- Ensure every hadm_id × drug_class combination exists (zeros where no prescriptions matched)
hadm_class_grid AS (
  SELECT
    c.hadm_id,
    cp.drug_class
  FROM
    cohort c
    CROSS JOIN class_patterns cp
),
hadm_class_flags AS (
  SELECT
    g.hadm_id,
    g.drug_class,
    COALESCE(pf.in_first, 0) AS in_first,
    COALESCE(pf.in_last, 0) AS in_last
  FROM
    hadm_class_grid g
    LEFT JOIN presc_flags pf
      ON g.hadm_id = pf.hadm_id
     AND g.drug_class = pf.drug_class
),
-- Final aggregation per drug class
agg AS (
  SELECT
    hcf.drug_class,
    COUNT(DISTINCT hcf.hadm_id) AS cohort_size,
    SUM(hcf.in_first) AS n_first24,
    SUM(hcf.in_last) AS n_last24,
    SUM(CASE WHEN hcf.in_first = 1 AND hcf.in_last = 1 THEN 1 ELSE 0 END) AS n_continued,
    SUM(CASE WHEN hcf.in_first = 0 AND hcf.in_last = 1 THEN 1 ELSE 0 END) AS n_initiated_late,
    SUM(CASE WHEN hcf.in_first = 1 AND hcf.in_last = 0 THEN 1 ELSE 0 END) AS n_discontinued
  FROM
    hadm_class_flags hcf
  GROUP BY
    hcf.drug_class
)
SELECT
  a.drug_class,
  a.cohort_size,
  a.n_first24,
  ROUND(100.0 * a.n_first24 / NULLIF(a.cohort_size, 0), 1) AS pct_on_first24,
  a.n_last24,
  ROUND(100.0 * a.n_last24 / NULLIF(a.cohort_size, 0), 1) AS pct_on_last24,
  a.n_continued,
  a.n_initiated_late AS n_initiated_late,
  a.n_discontinued AS n_discontinued
FROM
  agg a
ORDER BY
  a.drug_class;