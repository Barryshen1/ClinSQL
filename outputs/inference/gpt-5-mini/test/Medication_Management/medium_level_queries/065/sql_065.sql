WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 77 AND 87
    -- require diabetes diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
        AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(dicd.long_title) LIKE '%diabetes%'
    )
    -- require heart failure diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON d.icd_code = dicd.icd_code
        AND d.icd_version = dicd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND (
          LOWER(dicd.long_title) LIKE '%heart failure%'
          OR LOWER(dicd.long_title) LIKE '%congestive%'
        )
    )
),

-- Extract prescriptions for cohort admissions and classify as insulin vs oral agents
presc AS (
  SELECT
    c.hadm_id,
    c.admittime,
    p.starttime,
    p.stoptime,
    LOWER(COALESCE(p.drug, '')) AS drug_lower,
    CASE
      WHEN LOWER(COALESCE(p.drug, '')) LIKE '%insulin%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%novolog%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%lantus%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%humalog%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%humulin%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%novolin%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%detemir%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%glargine%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%degludec%'
      THEN 'insulin'
      WHEN LOWER(COALESCE(p.drug, '')) LIKE '%metformin%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%glipizide%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%glyburide%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%glimepiride%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%sitagliptin%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%saxagliptin%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%linagliptin%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%alogliptin%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%empagliflozin%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%dapagliflozin%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%canagliflozin%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%pioglitazone%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%rosiglitazone%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%repaglinide%'
        OR LOWER(COALESCE(p.drug, '')) LIKE '%nateglinide%'
      THEN 'oral'
      ELSE NULL
    END AS med_class
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = c.hadm_id
  WHERE p.starttime IS NOT NULL -- require timestamp to place events in windows
),

-- For each hadm and med_class determine baseline, 0-48h exposure, initiation in 0-48h, and 72h snapshot exposure
per_hadm AS (
  SELECT
    h.hadm_id,
    h.admittime,
    classes.med_class,
    -- baseline: any prescription start before admission
    MAX(CASE WHEN mc.starttime < h.admittime THEN 1 ELSE 0 END) > 0 AS baseline_exposed,
    -- prevalence in 0-48h window: any prescription overlapping [admit, admit+48h)
    MAX(CASE
      WHEN mc.starttime < TIMESTAMP_ADD(h.admittime, INTERVAL 48 HOUR)
       AND (mc.stoptime IS NULL OR mc.stoptime > h.admittime)
      THEN 1 ELSE 0 END) > 0 AS prevalence_0_48,
    -- initiation in 0-48h: a prescription that starts in [admit, admit+48h]
    MAX(CASE
      WHEN mc.starttime BETWEEN h.admittime AND TIMESTAMP_ADD(h.admittime, INTERVAL 48 HOUR)
      THEN 1 ELSE 0 END) > 0 AS any_start_in_0_48,
    -- snapshot at 72h: any prescription active at admit+72h
    MAX(CASE
      WHEN mc.starttime <= TIMESTAMP_ADD(h.admittime, INTERVAL 72 HOUR)
       AND (mc.stoptime IS NULL OR mc.stoptime > TIMESTAMP_ADD(h.admittime, INTERVAL 72 HOUR))
      THEN 1 ELSE 0 END) > 0 AS prevalence_at_72h
  FROM cohort h
  CROSS JOIN (SELECT 'insulin' AS med_class UNION ALL SELECT 'oral' AS med_class) as classes
  LEFT JOIN presc mc
    ON mc.hadm_id = h.hadm_id
    AND mc.med_class = classes.med_class
  GROUP BY h.hadm_id, h.admittime, classes.med_class
),

-- Summarize counts and percentages across the cohort
summary AS (
  SELECT
    med_class,
    COUNT(DISTINCT ph.hadm_id) AS cohort_size, -- will be repeated per class; same cohort_size for both classes
    SUM(CASE WHEN ph.baseline_exposed THEN 1 ELSE 0 END) AS n_baseline,
    SUM(CASE WHEN ph.any_start_in_0_48 = TRUE AND ph.baseline_exposed = FALSE THEN 1 ELSE 0 END) AS n_initiated_0_48,
    SUM(CASE WHEN ph.prevalence_0_48 = TRUE THEN 1 ELSE 0 END) AS n_prevalence_0_48,
    SUM(CASE WHEN ph.prevalence_at_72h = TRUE THEN 1 ELSE 0 END) AS n_prevalence_72h
  FROM per_hadm ph
  GROUP BY med_class
)

SELECT
  med_class,
  cohort_size,
  n_baseline,
  ROUND(100.0 * n_baseline / NULLIF(cohort_size, 0), 2) AS pct_baseline,
  n_initiated_0_48,
  ROUND(100.0 * n_initiated_0_48 / NULLIF(cohort_size - n_baseline, 0), 2) AS pct_initiated_0_48_among_not_baseline,
  n_prevalence_0_48,
  ROUND(100.0 * n_prevalence_0_48 / NULLIF(cohort_size, 0), 2) AS pct_prevalence_0_48,
  n_prevalence_72h,
  ROUND(100.0 * n_prevalence_72h / NULLIF(cohort_size, 0), 2) AS pct_prevalence_72h,
  -- net change in percentage points = prevalence_at_72h% - prevalence_0_48%
  ROUND(100.0 * n_prevalence_72h / NULLIF(cohort_size, 0)
        - 100.0 * n_prevalence_0_48 / NULLIF(cohort_size, 0), 2) AS net_change_pct_points_72h_minus_0_48
FROM summary
ORDER BY med_class;