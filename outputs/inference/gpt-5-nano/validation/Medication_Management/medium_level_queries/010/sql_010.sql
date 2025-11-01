WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE LOWER(p.gender) = 'f'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
    -- Must have T2DM during this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dcd
        ON di.icd_code = dcd.icd_code AND di.icd_version = dcd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dcd.long_title) LIKE '%type 2 diabetes mellitus%'
    )
    -- Must have HF during this admission
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dcd
        ON di.icd_code = dcd.icd_code AND di.icd_version = dcd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dcd.long_title) LIKE '%heart failure%'
    )
),
flags AS (
  SELECT
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,

    -- Insulin
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%'
             AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS insulin_first12,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%insulin%'
             AND pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
             THEN 1 ELSE 0 END) AS insulin_last48,

    -- Metformin
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%'
             AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS metformin_first12,
    MAX(CASE WHEN LOWER(pr.drug) LIKE '%metformin%'
             AND pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
             THEN 1 ELSE 0 END) AS metformin_last48,

    -- Sulfonylureas (SU)
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%'
                       OR LOWER(pr.drug) LIKE '%chlorpropamide%' OR LOWER(pr.drug) LIKE '%tolbutamide%')
             AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS su_first12,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%'
                       OR LOWER(pr.drug) LIKE '%chlorpropamide%' OR LOWER(pr.drug) LIKE '%tolbutamide%')
             AND pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
             THEN 1 ELSE 0 END) AS su_last48,

    -- DPP-4 inhibitors
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%')
             AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS dpp4_first12,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%')
             AND pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
             THEN 1 ELSE 0 END) AS dpp4_last48,

    -- SGLT2 inhibitors
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%')
             AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS sglt2_first12,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%')
             AND pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
             THEN 1 ELSE 0 END) AS sglt2_last48,

    -- GLP-1 receptor agonists
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%dulaglutide%'
                       OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%lixisenatide%')
             AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS glp1_first12,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%dulaglutide%'
                       OR LOWER(pr.drug) LIKE '%semaglutide%' OR LOWER(pr.drug) LIKE '%lixisenatide%')
             AND pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
             THEN 1 ELSE 0 END) AS glp1_last48,

    -- TZDs
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%')
             AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
             THEN 1 ELSE 0 END) AS tzd_first12,
    MAX(CASE WHEN (LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%')
             AND pr.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
             THEN 1 ELSE 0 END) AS tzd_last48
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.subject_id = c.subject_id
   AND pr.hadm_id = c.hadm_id
  GROUP BY c.hadm_id, c.subject_id, c.admittime, c.dischtime
)

SELECT
  class_label,
  AVG(first12) AS first12_pct,
  AVG(last48) AS last48_pct,
  AVG(last48) - AVG(first12) AS net_change_pp
FROM (
  SELECT hadm_id, subject_id, 'INSULIN' AS class_label, insulin_first12 AS first12, insulin_last48 AS last48 FROM flags
  UNION ALL
  SELECT hadm_id, subject_id, 'METFORMIN', metformin_first12, metformin_last48 FROM flags
  UNION ALL
  SELECT hadm_id, subject_id, 'SU', su_first12, su_last48 FROM flags
  UNION ALL
  SELECT hadm_id, subject_id, 'DPP4', dpp4_first12, dpp4_last48 FROM flags
  UNION ALL
  SELECT hadm_id, subject_id, 'SGLT2', sglt2_first12, sglt2_last48 FROM flags
  UNION ALL
  SELECT hadm_id, subject_id, 'GLP-1', glp1_first12, glp1_last48 FROM flags
  UNION ALL
  SELECT hadm_id, subject_id, 'TZD', tzd_first12, tzd_last48 FROM flags
) AS t
GROUP BY class_label
ORDER BY class_label;