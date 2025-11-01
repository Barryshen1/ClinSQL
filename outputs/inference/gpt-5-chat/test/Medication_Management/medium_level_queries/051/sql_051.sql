WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE (
        -- heart failure
        (d.icd_version = 9 AND d.icd_code LIKE '428%')
        OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
      )
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE (
        -- diabetes mellitus
        (d.icd_version = 9 AND d.icd_code LIKE '250%')
        OR (d.icd_version = 10 AND d.icd_code BETWEEN 'E08' AND 'E13' )
        OR (d.icd_version = 10 AND d.icd_code LIKE 'E08%')
        OR (d.icd_version = 10 AND d.icd_code LIKE 'E09%')
        OR (d.icd_version = 10 AND d.icd_code LIKE 'E10%')
        OR (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
        OR (d.icd_version = 10 AND d.icd_code LIKE 'E12%')
        OR (d.icd_version = 10 AND d.icd_code LIKE 'E13%')
      )
    )
),
rx_class AS (
  SELECT
    pr.subject_id,
    pr.hadm_id,
    pr.starttime,
    CASE
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(pr.drug) LIKE '%metformin%' 
        OR LOWER(pr.drug) LIKE '%glipizide%'
        OR LOWER(pr.drug) LIKE '%glyburide%'
        OR LOWER(pr.drug) LIKE '%glimepiride%'
        OR LOWER(pr.drug) LIKE '%pioglitazone%'
        OR LOWER(pr.drug) LIKE '%sitagliptin%'
        OR LOWER(pr.drug) LIKE '%linagliptin%'
        OR LOWER(pr.drug) LIKE '%repaglinide%'
        OR LOWER(pr.drug) LIKE '%nateglinide%'
        OR LOWER(pr.drug) LIKE '%dapagliflozin%'
        OR LOWER(pr.drug) LIKE '%empagliflozin%'
        OR LOWER(pr.drug) LIKE '%canagliflozin%'
        OR LOWER(pr.drug) LIKE '%alogliptin%'
      THEN 'Oral'
      ELSE NULL
    END AS med_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  WHERE pr.drug IS NOT NULL
),
flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX( CASE WHEN r.med_class = 'Insulin'
                 AND r.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
              THEN 1 ELSE 0 END ) AS early_insulin,
    MAX( CASE WHEN r.med_class = 'Oral'
                 AND r.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
              THEN 1 ELSE 0 END ) AS early_oral,
    MAX( CASE WHEN r.med_class = 'Insulin'
                 AND r.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime
              THEN 1 ELSE 0 END ) AS late_insulin,
    MAX( CASE WHEN r.med_class = 'Oral'
                 AND r.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime
              THEN 1 ELSE 0 END ) AS late_oral
  FROM cohort c
  LEFT JOIN rx_class r
    ON c.subject_id = r.subject_id AND c.hadm_id = r.hadm_id
  GROUP BY c.subject_id, c.hadm_id
),
class_rates AS (
  SELECT
    'early' AS phase,
    'Insulin' AS class,
    COUNTIF(early_insulin = 1) AS n,
    ROUND( COUNTIF(early_insulin = 1) / COUNT(*) * 100 , 1) AS pct
  FROM flags
  UNION ALL
  SELECT
    'early', 'Oral',
    COUNTIF(early_oral = 1),
    ROUND( COUNTIF(early_oral = 1) / COUNT(*) * 100 , 1)
  FROM flags
  UNION ALL
  SELECT
    'late', 'Insulin',
    COUNTIF(late_insulin = 1),
    ROUND( COUNTIF(late_insulin = 1) / COUNT(*) * 100 , 1)
  FROM flags
  UNION ALL
  SELECT
    'late', 'Oral',
    COUNTIF(late_oral = 1),
    ROUND( COUNTIF(late_oral = 1) / COUNT(*) * 100 , 1)
  FROM flags
),
transitions AS (
  SELECT
    CASE
      WHEN early_insulin=1 AND late_insulin=1 AND early_oral=0 AND late_oral=0 THEN 'Insulin -> Insulin'
      WHEN early_insulin=1 AND late_oral=1 AND early_oral=0 AND late_insulin=0 THEN 'Insulin -> Oral'
      WHEN early_oral=1 AND late_insulin=1 AND early_insulin=0 AND late_oral=0 THEN 'Oral -> Insulin'
      WHEN early_oral=1 AND late_oral=1 AND early_insulin=0 AND late_insulin=0 THEN 'Oral -> Oral'
      ELSE 'Other/Multiple/Both'
    END AS transition_type,
    COUNT(*) AS n
  FROM flags
  GROUP BY transition_type
)
SELECT
  '--- EARLY/LATE RATES ---' AS section, *
FROM class_rates
UNION ALL
SELECT
  '--- TRANSITIONS ---', transition_type AS phase, NULL AS class, n AS n, NULL AS pct
FROM transitions
ORDER BY section, phase;