WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    -- require T2DM diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
          -- ICD-10 T2DM codes E11*
          (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) = 'E11')
          -- ICD-9 diabetes codes 250*
          OR (di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) = '250')
          -- or diagnosis description mentioning diabetes + type 2 (broad text match)
          OR (LOWER(COALESCE(dd.long_title, '')) LIKE '%diabetes%' AND LOWER(COALESCE(dd.long_title, '')) LIKE '%type 2%')
          OR (LOWER(COALESCE(dd.long_title, '')) LIKE '%diabetes mellitus%')
        )
    )
    -- require Heart Failure diagnosis on this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
        AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (
          -- ICD-10 heart failure I50*
          (di.icd_version = 10 AND SUBSTR(di.icd_code, 1, 3) = 'I50')
          -- ICD-9 heart failure 428*
          OR (di.icd_version = 9 AND SUBSTR(di.icd_code, 1, 3) = '428')
          -- or text match
          OR (LOWER(COALESCE(dd.long_title, '')) LIKE '%heart failure%')
        )
    )
    -- ensure admission times available
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

-- Medication events from several sources. We normalize med name and restrict to events during the admission.
med_events AS (
  -- prescriptions
  SELECT
    pr.hadm_id,
    pr.starttime AS med_time,
    LOWER(COALESCE(pr.drug, '')) AS med_name_raw
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN cohort c ON pr.hadm_id = c.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime BETWEEN c.admittime AND c.dischtime

  UNION ALL

  -- pharmacy orders
  SELECT
    ph.hadm_id,
    ph.starttime AS med_time,
    LOWER(COALESCE(ph.medication, '')) AS med_name_raw
  FROM
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    JOIN cohort c ON ph.hadm_id = c.hadm_id
  WHERE ph.starttime IS NOT NULL
    AND ph.starttime BETWEEN c.admittime AND c.dischtime

  UNION ALL

  -- emar medication records (charttime)
  SELECT
    e.hadm_id,
    e.charttime AS med_time,
    LOWER(COALESCE(e.medication, '')) AS med_name_raw
  FROM
    `physionet-data.mimiciv_3_1_hosp.emar` e
    JOIN cohort c ON e.hadm_id = c.hadm_id
  WHERE e.charttime IS NOT NULL
    AND e.charttime BETWEEN c.admittime AND c.dischtime
),

-- Map med text to an antidiabetic class (only the classes of interest)
med_classified AS (
  SELECT
    me.hadm_id,
    me.med_time,
    me.med_name_raw,
    CASE
      WHEN me.med_name_raw LIKE '%metformin%' THEN 'metformin'
      WHEN me.med_name_raw LIKE '%glipizid%' THEN 'sulfonylurea'
      WHEN me.med_name_raw LIKE '%glimepirid%' THEN 'sulfonylurea'
      WHEN me.med_name_raw LIKE '%glyburi%' THEN 'sulfonylurea'
      WHEN me.med_name_raw LIKE '%gliclazid%' THEN 'sulfonylurea'
      WHEN me.med_name_raw LIKE '%glibenclamid%' THEN 'sulfonylurea'
      WHEN me.med_name_raw LIKE '%tolbutamid%' THEN 'sulfonylurea'
      WHEN me.med_name_raw LIKE '%chlorpropamid%' THEN 'sulfonylurea'
      WHEN me.med_name_raw LIKE '%gliptin%' THEN 'dpp4'
      -- SGLT2: common suffixes include 'gliflozin' or 'flozin'
      WHEN me.med_name_raw LIKE '%gliflozin%' OR me.med_name_raw LIKE '%flozin%' THEN 'sglt2'
      -- TZD class
      WHEN me.med_name_raw LIKE '%glitazone%' OR me.med_name_raw LIKE '%pioglitazone%' OR me.med_name_raw LIKE '%rosiglitazone%' THEN 'tzd'
      ELSE NULL
    END AS drug_class
  FROM med_events me
),

-- For each admission and class, determine presence in the first 72h and final 48h windows
class_by_window AS (
  SELECT
    c.hadm_id,
    mc.drug_class,
    -- indicator if any med of this class occurred in the first 72 hours after admission
    MAX(CASE
          WHEN mc.med_time BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) THEN 1
          ELSE 0
        END) AS any_first72,
    -- indicator if any med of this class occurred in the final 48 hours before discharge
    MAX(CASE
          WHEN mc.med_time BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime THEN 1
          ELSE 0
        END) AS any_final48
  FROM
    cohort c
    JOIN med_classified mc
      ON mc.hadm_id = c.hadm_id
  WHERE
    mc.drug_class IS NOT NULL
  GROUP BY
    c.hadm_id,
    mc.drug_class
),

-- Aggregate across admissions to get counts and prevalences per class
agg AS (
  SELECT
    cbw.drug_class,
    COUNTIF(cbw.any_first72 = 1) AS n_first72,
    COUNTIF(cbw.any_final48 = 1) AS n_final48
  FROM class_by_window cbw
  GROUP BY cbw.drug_class
),

denom AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_admissions
  FROM cohort
)

SELECT
  COALESCE(a.drug_class, 'unknown') AS drug_class,
  a.n_first72,
  a.n_final48,
  d.total_admissions AS denom_admissions,
  ROUND(100.0 * SAFE_DIVIDE(a.n_first72, d.total_admissions), 2) AS pct_first72,
  ROUND(100.0 * SAFE_DIVIDE(a.n_final48, d.total_admissions), 2) AS pct_final48,
  -- absolute percentage point difference between final48 and first72
  ROUND(ABS(100.0 * SAFE_DIVIDE(a.n_final48 - a.n_first72, d.total_admissions)), 2) AS absolute_pp_diff
FROM
  agg a,
  denom d
ORDER BY
  -- order by class for clarity (metformin first if present)
  CASE
    WHEN a.drug_class = 'metformin' THEN 1
    WHEN a.drug_class = 'sulfonylurea' THEN 2
    WHEN a.drug_class = 'dpp4' THEN 3
    WHEN a.drug_class = 'sglt2' THEN 4
    WHEN a.drug_class = 'tzd' THEN 5
    ELSE 99
  END;