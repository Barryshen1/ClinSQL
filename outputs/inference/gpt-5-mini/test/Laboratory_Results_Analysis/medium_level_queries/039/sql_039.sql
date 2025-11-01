WITH cohort AS (
  -- female patients age 87-97 at admission with primary diagnosis containing "chest pain"
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    p.anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      USING (subject_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      USING (hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddi
      ON di.icd_code = ddi.icd_code
      AND di.icd_version = ddi.icd_version
  WHERE
    LOWER(p.gender) = 'f'
    AND p.anchor_age BETWEEN 87 AND 97
    AND di.seq_num = 1 -- primary diagnosis
    AND LOWER(COALESCE(ddi.long_title, '')) LIKE '%chest pain%'
),
index_tn AS (
  -- earliest troponin lab within 24 hours of admission (numeric valuenum)
  SELECT
    c.subject_id,
    c.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    li.label AS lab_label,
    CASE
      WHEN le.valuenum <= 0.04 THEN 'Normal'
      WHEN le.valuenum > 0.04 AND le.valuenum <= 0.1 THEN 'Borderline'
      WHEN le.valuenum > 0.1 THEN 'Injury'
      ELSE 'Unknown'
    END AS category
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      USING (hadm_id)
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
      ON le.itemid = li.itemid
  WHERE
    LOWER(li.label) LIKE '%troponin%' -- capture troponin lab items
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY le.charttime ASC) = 1
),
totals AS (
  SELECT COUNT(*) AS total_n
  FROM index_tn
)
SELECT
  it.category,
  COUNT(*) AS n,
  ROUND(100.0 * COUNT(*) / NULLIF(t.total_n, 0), 2) AS pct_of_cohort_with_index_tn,
  ROUND(AVG(it.valuenum), 4) AS mean_tn,
  -- APPROX_QUANTILES returns array [min, Q1, median, Q3, max] when asked for 4 quantiles
  (APPROX_QUANTILES(it.valuenum, 4))[OFFSET(2)] AS median_tn,
  (APPROX_QUANTILES(it.valuenum, 4))[OFFSET(1)] AS q1_tn,
  (APPROX_QUANTILES(it.valuenum, 4))[OFFSET(3)] AS q3_tn,
  SAFE_CAST((APPROX_QUANTILES(it.valuenum, 4))[OFFSET(3)] - (APPROX_QUANTILES(it.valuenum, 4))[OFFSET(1)] AS FLOAT64) AS iqr_tn
FROM
  index_tn it
  CROSS JOIN totals t
GROUP BY
  it.category, t.total_n
ORDER BY
  -- desired logical ordering
  CASE it.category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Injury' THEN 3
    ELSE 4
  END;