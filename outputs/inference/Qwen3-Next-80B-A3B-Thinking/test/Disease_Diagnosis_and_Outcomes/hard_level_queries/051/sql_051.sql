WITH cohort AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 35 AND 45
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE
        di.hadm_id = a.hadm_id
        AND di.seq_num = 1
        AND di.icd_code LIKE 'K85%'
    )
),
diagnosis_counts AS (
  SELECT
    c.hadm_id,
    COUNT(*) AS total_diagnosis_count,
    SUM(CASE WHEN di.icd_code LIKE 'A41%' OR di.icd_code LIKE 'N17%' OR di.icd_code LIKE 'J96%' THEN 1 ELSE 0 END) AS major_complication_count
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON c.hadm_id = di.hadm_id
  GROUP BY
    c.hadm_id
),
risk_scores AS (
  SELECT
    dc.hadm_id,
    c.hospital_expire_flag,
    c.admittime,
    c.dischtime,
    dc.total_diagnosis_count,
    dc.major_complication_count,
    (dc.total_diagnosis_count + 5 * dc.major_complication_count) AS risk_score,
    NTILE(4) OVER (ORDER BY (dc.total_diagnosis_count + 5 * dc.major_complication_count)) AS risk_quartile,
    CASE WHEN c.hospital_expire_flag = 0 THEN TIMESTAMP_DIFF(c.dischtime, c.admittime, DAY) ELSE NULL END AS los_survivor
  FROM
    diagnosis_counts dc
  JOIN
    cohort c
    ON dc.hadm_id = c.hadm_id
)
SELECT
  CAST(risk_quartile AS STRING) AS risk_quartile,
  AVG(CAST(hospital_expire_flag AS INT64)) * 100 AS in_hospital_mortality,
  AVG(CAST(major_complication_count > 0 AS INT64)) * 100 AS major_complication_rate,
  PERCENTILE_CONT(los_survivor, 0.5) AS median_survivor_los
FROM
  risk_scores
GROUP BY
  risk_quartile
UNION ALL
SELECT
  'Overall' AS risk_quartile,
  AVG(CAST(hospital_expire_flag AS INT64)) * 100 AS in_hospital_mortality,
  AVG(CAST(major_complication_count > 0 AS INT64)) * 100 AS major_complication_rate,
  PERCENTILE_CONT(los_survivor, 0.5) AS median_survivor_los
FROM
  risk_scores;