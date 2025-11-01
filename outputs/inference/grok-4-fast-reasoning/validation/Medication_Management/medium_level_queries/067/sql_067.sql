WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.hadm_id IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 10 AND di.icd_code LIKE 'E[0-1][0-3]%')
          OR (di.icd_version = 9 AND (di.icd_code LIKE '249%' OR di.icd_code LIKE '250%'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dh
      WHERE dh.subject_id = a.subject_id
        AND dh.hadm_id = a.hadm_id
        AND (
          (dh.icd_version = 10 AND dh.icd_code LIKE 'I50%')
          OR (dh.icd_version = 9 AND dh.icd_code LIKE '428%')
        )
    )
),
total_patients AS (
  SELECT COUNT(DISTINCT hadm_id) AS total
  FROM cohort
),
classes AS (
  SELECT 'Insulin' AS antidiabetic_class UNION ALL
  SELECT 'Metformin' UNION ALL
  SELECT 'Sulfonylureas' UNION ALL
  SELECT 'DPP-4' UNION ALL
  SELECT 'SGLT2' UNION ALL
  SELECT 'GLP-1' UNION ALL
  SELECT 'TZDs'
),
med_by_class AS (
  -- Insulin
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ph.starttime,
    'Insulin' AS antidiabetic_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.subject_id = c.subject_id AND ph.hadm_id = c.hadm_id
  WHERE ph.starttime >= c.admittime
    AND ph.starttime < c.dischtime
    AND ph.starttime IS NOT NULL
    AND LOWER(ph.medication) LIKE '%insulin%'

  UNION ALL

  -- Metformin
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ph.starttime,
    'Metformin' AS antidiabetic_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.subject_id = c.subject_id AND ph.hadm_id = c.hadm_id
  WHERE ph.starttime >= c.admittime
    AND ph.starttime < c.dischtime
    AND ph.starttime IS NOT NULL
    AND LOWER(ph.medication) LIKE '%metformin%'

  UNION ALL

  -- Sulfonylureas
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ph.starttime,
    'Sulfonylureas' AS antidiabetic_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.subject_id = c.subject_id AND ph.hadm_id = c.hadm_id
  WHERE ph.starttime >= c.admittime
    AND ph.starttime < c.dischtime
    AND ph.starttime IS NOT NULL
    AND (
      LOWER(ph.medication) LIKE '%glipizide%'
      OR LOWER(ph.medication) LIKE '%glyburide%'
      OR LOWER(ph.medication) LIKE '%glimepiride%'
      OR LOWER(ph.medication) LIKE '%tolbutamide%'
      OR LOWER(ph.medication) LIKE '%tolazamide%'
      OR LOWER(ph.medication) LIKE '%chlorpropamide%'
    )

  UNION ALL

  -- DPP-4
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ph.starttime,
    'DPP-4' AS antidiabetic_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.subject_id = c.subject_id AND ph.hadm_id = c.hadm_id
  WHERE ph.starttime >= c.admittime
    AND ph.starttime < c.dischtime
    AND ph.starttime IS NOT NULL
    AND (
      LOWER(ph.medication) LIKE '%sitagliptin%'
      OR LOWER(ph.medication) LIKE '%saxagliptin%'
      OR LOWER(ph.medication) LIKE '%linagliptin%'
      OR LOWER(ph.medication) LIKE '%alogliptin%'
    )

  UNION ALL

  -- SGLT2
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ph.starttime,
    'SGLT2' AS antidiabetic_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.subject_id = c.subject_id AND ph.hadm_id = c.hadm_id
  WHERE ph.starttime >= c.admittime
    AND ph.starttime < c.dischtime
    AND ph.starttime IS NOT NULL
    AND (
      LOWER(ph.medication) LIKE '%canagliflozin%'
      OR LOWER(ph.medication) LIKE '%dapagliflozin%'
      OR LOWER(ph.medication) LIKE '%empagliflozin%'
      OR LOWER(ph.medication) LIKE '%ertugliflozin%'
    )

  UNION ALL

  -- GLP-1
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ph.starttime,
    'GLP-1' AS antidiabetic_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.subject_id = c.subject_id AND ph.hadm_id = c.hadm_id
  WHERE ph.starttime >= c.admittime
    AND ph.starttime < c.dischtime
    AND ph.starttime IS NOT NULL
    AND (
      LOWER(ph.medication) LIKE '%exenatide%'
      OR LOWER(ph.medication) LIKE '%liraglutide%'
      OR LOWER(ph.medication) LIKE '%dulaglutide%'
      OR LOWER(ph.medication) LIKE '%semaglutide%'
      OR LOWER(ph.medication) LIKE '%albiglutide%'
      OR LOWER(ph.medication) LIKE '%lixisenatide%'
    )

  UNION ALL

  -- TZDs
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    ph.starttime,
    'TZDs' AS antidiabetic_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` ph
    ON ph.subject_id = c.subject_id AND ph.hadm_id = c.hadm_id
  WHERE ph.starttime >= c.admittime
    AND ph.starttime < c.dischtime
    AND ph.starttime IS NOT NULL
    AND (
      LOWER(ph.medication) LIKE '%pioglitazone%'
      OR LOWER(ph.medication) LIKE '%rosiglitazone%'
    )
),
first_initiations AS (
  SELECT
    hadm_id,
    antidiabetic_class,
    MIN(starttime) AS first_start
  FROM med_by_class
  GROUP BY hadm_id, antidiabetic_class
),
period_inits AS (
  SELECT
    fi.hadm_id,
    fi.antidiabetic_class,
    fi.first_start,
    c.admittime,
    c.dischtime,
    CASE
      WHEN fi.first_start >= c.admittime
        AND fi.first_start <= TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
      THEN 1
    END AS in_first12,
    CASE
      WHEN fi.first_start >= TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR)
        AND fi.first_start < c.dischtime
      THEN 1
    END AS in_last48
  FROM first_initiations fi
  INNER JOIN cohort c
    ON fi.hadm_id = c.hadm_id
),
aggregated AS (
  SELECT
    antidiabetic_class,
    SUM(in_first12) AS count_first12,
    SUM(in_last48) AS count_last48
  FROM period_inits
  GROUP BY antidiabetic_class
)
SELECT
  c.antidiabetic_class,
  ROUND(COALESCE(a.count_first12, 0) * 100.0 / tp.total, 2) AS first12_pct,
  ROUND(COALESCE(a.count_last48, 0) * 100.0 / tp.total, 2) AS last48_pct
FROM classes c
LEFT JOIN aggregated a
  ON c.antidiabetic_class = a.antidiabetic_class
CROSS JOIN total_patients tp
ORDER BY c.antidiabetic_class;