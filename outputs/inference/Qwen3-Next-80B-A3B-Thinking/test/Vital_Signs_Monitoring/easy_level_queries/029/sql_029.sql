WITH first_spO2 AS (
  SELECT
    p.subject_id,
    c.valuenum,
    ROW_NUMBER() OVER (PARTITION BY p.subject_id ORDER BY c.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON p.subject_id = c.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 62 AND 72
    AND d.label = 'SpO2'
    AND c.valuenum IS NOT NULL
)
SELECT
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS q1,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) AS q3,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS iqr
FROM first_spO2
WHERE rn = 1;