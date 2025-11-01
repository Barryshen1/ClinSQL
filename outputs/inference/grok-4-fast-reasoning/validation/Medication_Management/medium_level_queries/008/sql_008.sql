WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = '10' AND d.icd_code LIKE 'E11%') OR
          (d.icd_version = '9' AND d.icd_code LIKE '250%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = '10' AND d.icd_code LIKE 'I50%') OR
          (d.icd_version = '9' AND d.icd_code LIKE '428%')
        )
    )
),
patient_meds AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    MAX(CASE
      WHEN e.charttime >= c.admittime
        AND e.charttime < c.admittime + INTERVAL 24 HOUR
        AND LOWER(e.medication) LIKE '%insulin%'
      THEN 1
      ELSE 0
    END) AS insulin_first,
    MAX(CASE
      WHEN e.charttime >= c.dischtime - INTERVAL 48 HOUR
        AND e.charttime < c.dischtime
        AND LOWER(e.medication) LIKE '%insulin%'
      THEN 1
      ELSE 0
    END) AS insulin_last,
    MAX(CASE
      WHEN e.charttime >= c.admittime
        AND e.charttime < c.admittime + INTERVAL 24 HOUR
        AND LOWER(ed.route) LIKE '%po%'
        AND (
          LOWER(e.medication) LIKE '%metformin%'
          OR LOWER(e.medication) LIKE '%glipizide%'
          OR LOWER(e.medication) LIKE '%glyburide%'
          OR LOWER(e.medication) LIKE '%glimepiride%'
          OR LOWER(e.medication) LIKE '%pioglitazone%'
          OR LOWER(e.medication) LIKE '%sitagliptin%'
          OR LOWER(e.medication) LIKE '%linagliptin%'
          OR LOWER(e.medication) LIKE '%dapagliflozin%'
          OR LOWER(e.medication) LIKE '%empagliflozin%'
          OR LOWER(e.medication) LIKE '%acarbose%'
          OR LOWER(e.medication) LIKE '%repaglinide%'
        )
      THEN 1
      ELSE 0
    END) AS oral_first,
    MAX(CASE
      WHEN e.charttime >= c.dischtime - INTERVAL 48 HOUR
        AND e.charttime < c.dischtime
        AND LOWER(ed.route) LIKE '%po%'
        AND (
          LOWER(e.medication) LIKE '%metformin%'
          OR LOWER(e.medication) LIKE '%glipizide%'
          OR LOWER(e.medication) LIKE '%glyburide%'
          OR LOWER(e.medication) LIKE '%glimepiride%'
          OR LOWER(e.medication) LIKE '%pioglitazone%'
          OR LOWER(e.medication) LIKE '%sitagliptin%'
          OR LOWER(e.medication) LIKE '%linagliptin%'
          OR LOWER(e.medication) LIKE '%dapagliflozin%'
          OR LOWER(e.medication) LIKE '%empagliflozin%'
          OR LOWER(e.medication) LIKE '%acarbose%'
          OR LOWER(e.medication) LIKE '%repaglinide%'
        )
      THEN 1
      ELSE 0
    END) AS oral_last
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.subject_id = e.subject_id
    AND c.hadm_id = e.hadm_id
    AND e.charttime >= c.admittime
    AND e.charttime < c.dischtime
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON e.emar_id = ed.emar_id
    AND e.emar_seq = ed.emar_seq
  GROUP BY c.subject_id, c.hadm_id, c.admittime, c.dischtime
)
SELECT 'Total Admissions' AS metric, COUNT(*) AS value FROM patient_meds
UNION ALL
SELECT 'First 24h Insulin %' AS metric, ROUND(100.0 * AVG(insulin_first), 2) AS value FROM patient_meds
UNION ALL
SELECT 'Last 48h Insulin %' AS metric, ROUND(100.0 * AVG(insulin_last), 2) AS value FROM patient_meds
UNION ALL
SELECT 'First 24h Oral %' AS metric, ROUND(100.0 * AVG(oral_first), 2) AS value FROM patient_meds
UNION ALL
SELECT 'Last 48h Oral %' AS metric, ROUND(100.0 * AVG(oral_last), 2) AS value FROM patient_meds
UNION ALL
SELECT 'Insulin Continued' AS metric, SUM(CASE WHEN insulin_first = 1 AND insulin_last = 1 THEN 1 ELSE 0 END) AS value FROM patient_meds
UNION ALL
SELECT 'Insulin Initiated' AS metric, SUM(CASE WHEN insulin_first = 0 AND insulin_last = 1 THEN 1 ELSE 0 END) AS value FROM patient_meds
UNION ALL
SELECT 'Insulin Discontinued' AS metric, SUM(CASE WHEN insulin_first = 1 AND insulin_last = 0 THEN 1 ELSE 0 END) AS value FROM patient_meds
UNION ALL
SELECT 'Oral Continued' AS metric, SUM(CASE WHEN oral_first = 1 AND oral_last = 1 THEN 1 ELSE 0 END) AS value FROM patient_meds
UNION ALL
SELECT 'Oral Initiated' AS metric, SUM(CASE WHEN oral_first = 0 AND oral_last = 1 THEN 1 ELSE 0 END) AS value FROM patient_meds
UNION ALL
SELECT 'Oral Discontinued' AS metric, SUM(CASE WHEN oral_first = 1 AND oral_last = 0 THEN 1 ELSE 0 END) AS value FROM patient_meds;