WITH cohort AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 47 AND 57
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code >= '410' AND d.icd_code < '415')
      OR 
      (d.icd_version = 10 AND d.icd_code >= 'I20' AND d.icd_code < 'I26')
    )
),
first_trop AS (
  SELECT 
    l.hadm_id,
    l.valuenum AS first_trop_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  WHERE l.itemid = 50341
    AND l.valuenum IS NOT NULL
    AND l.charttime IS NOT NULL
    AND l.hadm_id IN (SELECT hadm_id FROM cohort)
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY l.hadm_id 
    ORDER BY l.charttime, l.storetime
  ) = 1
),
filtered_trop AS (
  SELECT first_trop_value
  FROM first_trop
  WHERE first_trop_value > 0.014
)
SELECT
  PERCENTILE_CONT(first_trop_value, 0.5) OVER w AS median,
  PERCENTILE_CONT(first_trop_value, 0.75) OVER w - PERCENTILE_CONT(first_trop_value, 0.25) OVER w AS iqr
FROM filtered_trop
WINDOW w AS (ORDER BY first_trop_value ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING)
LIMIT 1;