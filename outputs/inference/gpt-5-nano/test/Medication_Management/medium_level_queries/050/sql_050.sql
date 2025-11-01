WITH Cohort AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.subject_id = a.subject_id AND di.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND (
      LOWER(dd.long_title) LIKE '%type 2 diabetes%' OR di.icd_code LIKE 'E11%'
    )
    AND (
      LOWER(dd.long_title) LIKE '%heart failure%' OR di.icd_code LIKE 'I50%'
    )
),

-- 2) Map prescriptions to one of the four classes (Antidiabetic, BetaBlocker, ACEi/ARB/ARNI, LoopDiuretic)
-- and carry along admission times for window calculations
ClassEntries AS (
  SELECT
    a.hadm_id,
    CASE
      -- Antidiabetic
      WHEN LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%insulin%' OR
           LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%' OR
           LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%pioglitazone%' OR
           LOWER(pr.drug) LIKE '%rosiglitazone%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR
           LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR
           LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%'
        THEN 'Antidiabetic'
      -- Beta-blocker
      WHEN LOWER(pr.drug) LIKE '%metoprolol%' OR LOWER(pr.drug) LIKE '%atenolol%' OR
           LOWER(pr.drug) LIKE '%propranolol%' OR LOWER(pr.drug) LIKE '%bisoprolol%' OR
           LOWER(pr.drug) LIKE '%carvedilol%' OR LOWER(pr.drug) LIKE '%labetalol%' OR
           LOWER(pr.drug) LIKE '%nebivolol%'
        THEN 'BetaBlocker'
      -- ACEi/ARB/ARNI
      WHEN LOWER(pr.drug) LIKE '%sacubitril%' OR LOWER(pr.drug) LIKE '%valsartan%' OR
           LOWER(pr.drug) LIKE '%losartan%' OR LOWER(pr.drug) LIKE '%olmesartan%' OR
           LOWER(pr.drug) LIKE '%telmisartan%' OR LOWER(pr.drug) LIKE '%irbesartan%' OR
           LOWER(pr.drug) LIKE '%candesartan%' OR LOWER(pr.drug) LIKE '%ramipril%' OR
           LOWER(pr.drug) LIKE '%lisinopril%' OR LOWER(pr.drug) LIKE '%enalapril%' OR
           LOWER(pr.drug) LIKE '%benazepril%'
        THEN 'ACE_ARB_ARNI'
      -- Loop diuretic
      WHEN LOWER(pr.drug) LIKE '%furosemide%' OR LOWER(pr.drug) LIKE '%bumetanide%' OR
           LOWER(pr.drug) LIKE '%torsemide%'
        THEN 'LoopDiuretic'
      ELSE NULL
    END AS class_label,
    pr.starttime,
    pr.stoptime,
    a.admittime,
    a.dischtime
  FROM Cohort a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
    ON pr.hadm_id = a.hadm_id
  WHERE pr.drug IS NOT NULL
)

, Overlaps AS (
  -- 3) Compute overlap presence in first 24h and final 48h for each (hadm_id, class)
  SELECT
    ce.hadm_id,
    ce.class_label,
    -- overlap in first 24h window
    MAX(IF(pr_start < TIMESTAMP_ADD(ce.admittime, INTERVAL 24 HOUR)
           AND pr_stop > ce.admittime, 1, 0)) AS first24,
    -- overlap in final 48h window
    MAX(IF(pr_start < ce.dischtime
           AND pr_stop > TIMESTAMP_SUB(ce.dischtime, INTERVAL 48 HOUR), 1, 0)) AS final48
  FROM (
    SELECT
      h.hadm_id,
      h.class_label,
      h.starttime AS pr_start,
      h.stoptime AS pr_stop,
      h.admittime,
      h.dischtime
    FROM ClassEntries h
  ) AS ce
  GROUP BY hadm_id, class_label
)

, AllPairs AS (
  -- 4) Ensure we have a row for every hadm_id x class combination
  SELECT h.hadm_id, cl.class_label
  FROM (SELECT DISTINCT hadm_id FROM Cohort) h
  CROSS JOIN (
    SELECT 'Antidiabetic' AS class_label UNION ALL
    SELECT 'BetaBlocker' UNION ALL
    SELECT 'ACE_ARB_ARNI' UNION ALL
    SELECT 'LoopDiuretic'
  ) AS cl
)

, PairsWithOverlaps AS (
  -- Join to get first24/final48 per hadm_id/class, fill missing with 0
  SELECT
    p.hadm_id,
    p.class_label,
    IFNULL(o.first24, 0) AS first24,
    IFNULL(o.final48, 0) AS final48
  FROM AllPairs p
  LEFT JOIN Overlaps o
    ON o.hadm_id = p.hadm_id
   AND o.class_label = p.class_label
)

SELECT
  class_label,
  COUNT(*) AS n_patients,
  ROUND(AVG(first24) * 100, 1) AS first24_percent,
  ROUND(AVG(final48) * 100, 1) AS final48_percent,
  SUM(CASE WHEN first24 = 1 AND final48 = 1 THEN 1 ELSE 0 END) AS continued_count,
  SUM(CASE WHEN first24 = 0 AND final48 = 1 THEN 1 ELSE 0 END) AS initiated_count,
  SUM(CASE WHEN first24 = 1 AND final48 = 0 THEN 1 ELSE 0 END) AS discontinued_count
FROM PairsWithOverlaps
GROUP BY class_label
ORDER BY class_label;