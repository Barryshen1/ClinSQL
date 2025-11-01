WITH sepsis_patients AS (
  SELECT DISTINCT
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON p.subject_id = d.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 43
    AND d.icd_code = 'A41.9' -- Sepsis code
),
platelet_counts AS (
  SELECT
    le.subject_id,
    le.valuenum AS platelet_count
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` AS le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS dli
    ON le.itemid = dli.itemid
  WHERE
    le.subject_id IN (SELECT subject_id FROM sepsis_patients)
    AND dli.label = 'Platelet count'
),
peak_platelet_counts AS (
  SELECT
    subject_id,
    MAX(platelet_count) AS peak_platelet_count
  FROM platelet_counts
  GROUP BY
    subject_id
)
SELECT
  APPROX_QUANTILES(peak_platelet_count, 4)[OFFSET(3)] AS percentile_75
FROM peak_platelet_counts;