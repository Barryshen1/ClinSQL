WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender IN ('Female', 'F')
    AND p.anchor_age BETWEEN 86 AND 96
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic
        ON di.icd_code = dic.icd_code
       AND di.icd_version = dic.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND LOWER(dic.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dic2
        ON di2.icd_code = dic2.icd_code
       AND di2.icd_version = dic2.icd_version
      WHERE di2.subject_id = a.subject_id
        AND di2.hadm_id = a.hadm_id
        AND (LOWER(dic2.long_title) LIKE '%heart failure%'
             OR LOWER(dic2.long_title) LIKE '%congestive heart failure%')
    )
),
early_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE
          WHEN LOWER(ph.medication) LIKE '%insulin%' THEN 1
          ELSE 0
        END) AS has_insulin_early,
    MAX(CASE
          WHEN LOWER(ph.medication) LIKE '%metformin%'
               OR LOWER(ph.medication) LIKE '%glyburide%'
               OR LOWER(ph.medication) LIKE '%glipizide%'
               OR LOWER(ph.medication) LIKE '%glimepiride%'
               OR LOWER(ph.medication) LIKE '%pioglitazone%'
               OR LOWER(ph.medication) LIKE '%rosiglitazone%'
               OR LOWER(ph.medication) LIKE '%sitagliptin%'
               OR LOWER(ph.medication) LIKE '%gliptin%'
          THEN 1
          ELSE 0
        END) AS has_oral_early
  FROM
    cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` AS ph
    ON ph.subject_id = c.subject_id
   AND ph.hadm_id = c.hadm_id
   AND ph.starttime >= c.admittime
   AND ph.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 12 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
late_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE
          WHEN LOWER(ph.medication) LIKE '%insulin%' THEN 1
          ELSE 0
        END) AS has_insulin_late,
    MAX(CASE
          WHEN LOWER(ph.medication) LIKE '%metformin%'
               OR LOWER(ph.medication) LIKE '%glyburide%'
               OR LOWER(ph.medication) LIKE '%glipizide%'
               OR LOWER(ph.medication) LIKE '%glimepiride%'
               OR LOWER(ph.medication) LIKE '%pioglitazone%'
               OR LOWER(ph.medication) LIKE '%rosiglitazone%'
               OR LOWER(ph.medication) LIKE '%sitagliptin%'
               OR LOWER(ph.medication) LIKE '%gliptin%'
          THEN 1
          ELSE 0
        END) AS has_oral_late
  FROM
    cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` AS ph
    ON ph.subject_id = c.subject_id
   AND ph.hadm_id = c.hadm_id
   AND ph.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 72 HOUR)
   AND ph.starttime <= c.dischtime
  GROUP BY c.subject_id, c.hadm_id
),
merged AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    CASE
      WHEN lf.has_insulin_late = 1 THEN 'Insulin'
      WHEN lf.has_insulin_late = 0 AND lf.has_oral_late = 1 THEN 'Oral'
      WHEN lf.has_insulin_late = 0 AND lf.has_oral_late = 0 THEN 'None'
      ELSE 'Insulin'
    END AS late_class,
    CASE
      WHEN ef.has_insulin_early = 1 THEN 'Insulin'
      WHEN ef.has_insulin_early = 0 AND ef.has_oral_early = 1 THEN 'Oral'
      WHEN ef.has_insulin_early = 0 AND ef.has_oral_early = 0 THEN 'None'
      ELSE 'Insulin'
    END AS early_class
  FROM cohort c
  LEFT JOIN early_flags ef
    ON ef.subject_id = c.subject_id
   AND ef.hadm_id = c.hadm_id
  LEFT JOIN late_flags lf
    ON lf.subject_id = c.subject_id
   AND lf.hadm_id = c.hadm_id
)
SELECT
  (SUM(CASE WHEN early_class = 'Insulin' THEN 1 ELSE 0 END) * 1.0) / COUNT(*) * 100.0 AS early_rate_insulin,
  (SUM(CASE WHEN early_class = 'Oral' THEN 1 ELSE 0 END) * 1.0) / COUNT(*) * 100.0 AS early_rate_oral,
  (SUM(CASE WHEN late_class = 'Insulin' THEN 1 ELSE 0 END) * 1.0) / COUNT(*) * 100.0 AS late_rate_insulin,
  (SUM(CASE WHEN late_class = 'Oral' THEN 1 ELSE 0 END) * 1.0) / COUNT(*) * 100.0 AS late_rate_oral,
  (SUM(CASE WHEN early_class = 'Insulin' AND late_class = 'Oral' THEN 1 ELSE 0 END) * 1.0) / COUNT(*) * 100.0 AS transition_insulin_to_oral,
  (SUM(CASE WHEN early_class = 'Oral' AND late_class = 'Insulin' THEN 1 ELSE 0 END) * 1.0) / COUNT(*) * 100.0 AS transition_oral_to_insulin,
  COUNT(*) AS cohort_size
FROM merged;