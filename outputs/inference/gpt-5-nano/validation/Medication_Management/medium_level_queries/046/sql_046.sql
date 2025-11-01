WITH cohort AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 63 AND 73
    AND a.dischtime IS NOT NULL
    -- Must have Type 2 Diabetes diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON di.icd_code = dd.icd_code
       AND di.icd_version = dd.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND (dd.long_title LIKE '%type 2 diabetes%' OR dd.long_title LIKE '%diabetes mellitus type 2%' OR dd.long_title LIKE '%diabetes%')
    )
    -- Must have Heart Failure diagnosis
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd2
        ON di2.icd_code = dd2.icd_code
       AND di2.icd_version = dd2.icd_version
      WHERE di2.hadm_id = a.hadm_id
        AND dd2.long_title LIKE '%heart failure%'
    )
),

grid AS (
  SELECT hadm_id, 'Insulin' AS med_group FROM cohort
  UNION ALL
  SELECT hadm_id, 'Oral' AS med_group FROM cohort
),

prescriptions_sub AS (
  SELECT
    hadm_id,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' OR
           LOWER(drug) LIKE '%glipizide%' OR
           LOWER(drug) LIKE '%glyburide%' OR
           LOWER(drug) LIKE '%glimepiride%' OR
           LOWER(drug) LIKE '%pioglitazone%' OR
           LOWER(drug) LIKE '%rosiglitazone%' OR
           LOWER(drug) LIKE '%sitagliptin%' OR
           LOWER(drug) LIKE '%linagliptin%' OR
           LOWER(drug) LIKE '%acarbose%' OR
           LOWER(drug) LIKE '%repaglinide%' THEN 'Oral'
      ELSE NULL
    END AS med_group,
    starttime,
    stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IS NOT NULL
),

presence AS (
  SELECT g.hadm_id,
         g.med_group,
         MAX(CASE
               WHEN g.med_group = 'Insulin'
                    AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
                    AND IFNULL(p.stoptime, c.admittime) >= c.admittime
               THEN 1 ELSE 0 END) AS insulin_first24,
         MAX(CASE
               WHEN g.med_group = 'Insulin'
                    AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
                    AND IFNULL(p.stoptime, c.admittime) >= c.admittime
               THEN 1 ELSE 0 END) AS insulin_last24,
         MAX(CASE
               WHEN g.med_group = 'Oral'
                    AND p.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 1 DAY)
                    AND IFNULL(p.stoptime, c.admittime) >= c.admittime
               THEN 1 ELSE 0 END) AS oral_first24,
         MAX(CASE
               WHEN g.med_group = 'Oral'
                    AND p.starttime < c.dischtime
                    AND IFNULL(p.stoptime, c.dischtime) >= TIMESTAMP_SUB(c.dischtime, INTERVAL 1 DAY)
               THEN 1 ELSE 0 END) AS oral_last24
  FROM grid g
  JOIN cohort c ON g.hadm_id = c.hadm_id
  LEFT JOIN prescriptions_sub p
    ON p.hadm_id = g.hadm_id
   AND p.med_group = g.med_group
  GROUP BY g.hadm_id, g.med_group
),

insulin_stats AS (
  SELECT 'Insulin' AS med_group,
         100.0 * SUM(insulin_first24) / COUNT(*) AS first24_pct,
         100.0 * SUM(insulin_last24)  / COUNT(*) AS last24_pct
  FROM presence
  WHERE med_group = 'Insulin'
),
oral_stats AS (
  SELECT 'Oral' AS med_group,
         100.0 * SUM(oral_first24) / COUNT(*) AS first24_pct,
         100.0 * SUM(oral_last24)  / COUNT(*) AS last24_pct
  FROM presence
  WHERE med_group = 'Oral'
)

SELECT med_group,
       first24_pct,
       last24_pct,
       (last24_pct - first24_pct) AS net_change_pp
FROM insulin_stats
UNION ALL
SELECT med_group,
       first24_pct,
       last24_pct,
       (last24_pct - first24_pct) AS net_change_pp
FROM oral_stats
ORDER BY med_group;