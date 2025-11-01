WITH eligible AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND (p.anchor_age IS NOT NULL)
    AND (p.anchor_year IS NOT NULL)
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 81 AND 91
    AND (dd.long_title LIKE '%Chest pain%' OR dd.long_title LIKE '%Myocardial infarction%')
),
troponin_first AS (
  SELECT t.hadm_id, t.valuenum
  FROM (
    SELECT le.hadm_id, le.valuenum,
           ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
    FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
      ON le.itemid = dli.itemid
    WHERE le.hadm_id IN (SELECT hadm_id FROM eligible)
      AND REGEXP_CONTAINS(dli.label, r'(?i)troponin.*t')
  ) AS t
  WHERE t.rn = 1
),
summary AS (
  SELECT
    CASE
      WHEN tf.valuenum <= 14 THEN 'Normal'
      WHEN tf.valuenum < 53 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END AS hsTnT_index_category,
    COUNT(*) AS n,
    AVG(TIMESTAMP_DIFF(e.dischtime, e.admittime, SECOND) / 86400.0) AS mean_los_days
  FROM eligible e
  JOIN troponin_first tf ON e.hadm_id = tf.hadm_id
  GROUP BY
    CASE
      WHEN tf.valuenum <= 14 THEN 'Normal'
      WHEN tf.valuenum < 53 THEN 'Borderline'
      ELSE 'Myocardial Injury'
    END
),
tot AS (
  SELECT COUNT(*) AS total_n FROM eligible
)
SELECT
  hsTnT_index_category,
  n,
  ROUND(100.0 * n / tot.total_n, 2) AS pct,
  mean_los_days
FROM summary
CROSS JOIN tot
ORDER BY hsTnT_index_category;