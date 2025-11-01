WITH spo2_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%spo2%' OR
    LOWER(label) LIKE '%o2 sat%' OR
    LOWER(label) LIKE '%oxygen saturation%' OR
    LOWER(label) LIKE '%pulse ox%' OR
    LOWER(abbreviation) LIKE '%spo2%' OR
    LOWER(abbreviation) LIKE '%o2%'
),
first_spo2_per_subject AS (
  SELECT
    ce.subject_id,
    ce.valuenum AS spo2,
    ce.charttime,
    ROW_NUMBER() OVER (PARTITION BY ce.subject_id ORDER BY ce.charttime) AS rn
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN
    spo2_items si
  USING (itemid)
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  USING (subject_id)
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum <= 100
)
SELECT
  q[OFFSET(1)] AS q1_25,
  q[OFFSET(3)] AS q3_75,
  SAFE_CAST(q[OFFSET(3)] - q[OFFSET(1)] AS FLOAT64) AS iqr,
  n_subjects
FROM (
  SELECT
    APPROX_QUANTILES(spo2, 4) AS q,
    COUNT(*) AS n_subjects
  FROM first_spo2_per_subject
  WHERE rn = 1
);