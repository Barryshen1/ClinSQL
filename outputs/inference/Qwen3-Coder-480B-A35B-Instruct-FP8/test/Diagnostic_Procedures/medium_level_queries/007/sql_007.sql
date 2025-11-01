WITH cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8 days'
    END AS los_category,
    di.seq_num AS diagnosis_seq_num
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON
    p.subject_id = a.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  ON
    a.hadm_id = di.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
  ON
    di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 50 AND 60
    AND LOWER(d.long_title) LIKE '%acute coronary syndrome%'
),

procedure_counts AS (
  SELECT
    c.hadm_id,
    c.los_category,
    CASE WHEN c.diagnosis_seq_num = 1 THEN 'Primary' ELSE 'Secondary' END AS diagnosis_position,
    COUNT(pr.icd_code) AS proc_count
  FROM
    cohort c
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` pr
  ON
    c.hadm_id = pr.hadm_id
  WHERE
    c.los_category IS NOT NULL
  GROUP BY
    c.hadm_id, c.los_category, diagnosis_position
)

SELECT
  los_category,
  diagnosis_position,
  APPROX_QUANTILES(proc_count, 100)[OFFSET(25)] AS p25,
  APPROX_QUANTILES(proc_count, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(proc_count, 100)[OFFSET(75)] AS p75
FROM
  procedure_counts
GROUP BY
  los_category, diagnosis_position
ORDER BY
  los_category, diagnosis_position;