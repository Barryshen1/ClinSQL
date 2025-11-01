WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
    ON a.subject_id = d.subject_id
    AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND d.seq_num = 1
    AND d.icd_code IN ('5780', '5781', '5789')  -- ICD-9 codes for upper GI hemorrhage
)
SELECT
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS los_25th_percentile
FROM
  cohort;