WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    a.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 85 AND 95
    AND (
      dd.icd_code LIKE 'J45%' OR dd.icd_code LIKE 'J46%' -- Asthma
    )
),

-- Map ICD codes to CCI weights (simplified version)
cci_scores AS (
  SELECT
    d.hadm_id,
    SUM(
      CASE
        WHEN dd.icd_code IN ('I21%', 'I22%', 'I25.2') THEN 1 -- MI
        WHEN dd.icd_code LIKE 'I60%' OR dd.icd_code LIKE 'I61%' OR dd.icd_code LIKE 'I63%' OR dd.icd_code LIKE 'I64%' THEN 1 -- Cerebrovascular disease
        WHEN dd.icd_code LIKE 'I10%' OR dd.icd_code LIKE 'I11%' THEN 1 -- CHF
        WHEN dd.icd_code LIKE 'C%' AND dd.icd_code NOT LIKE 'C77%' AND dd.icd_code NOT LIKE 'C78%' AND dd.icd_code NOT LIKE 'C79%' THEN 1 -- Cancer
        WHEN dd.icd_code LIKE 'J44%' THEN 1 -- Chronic pulmonary disease
        WHEN dd.icd_code LIKE 'I50%' THEN 1 -- CHF
        WHEN dd.icd_code LIKE 'E10%' OR dd.icd_code LIKE 'E11%' OR dd.icd_code LIKE 'E14%' THEN 1 -- Diabetes
        WHEN dd.icd_code LIKE 'E10.2%' OR dd.icd_code LIKE 'E11.2%' OR dd.icd_code LIKE 'E14.2%' THEN 1 -- Diabetes with complications
        WHEN dd.icd_code LIKE 'I95.0%' OR dd.icd_code LIKE 'I95.1%' THEN 1 -- Chronic renal disease
        WHEN dd.icd_code LIKE 'K70.3%' OR dd.icd_code LIKE 'K74.0%' OR dd.icd_code LIKE 'K74.2%' OR dd.icd_code LIKE 'K74.6%' THEN 1 -- Liver disease
        WHEN dd.icd_code LIKE 'G81%' OR dd.icd_code LIKE 'G82%' THEN 1 -- Hemiplegia
        WHEN dd.icd_code LIKE 'I69.0%' OR dd.icd_code LIKE 'I69.1%' OR dd.icd_code LIKE 'I69.2%' OR dd.icd_code LIKE 'I69.3%' OR dd.icd_code LIKE 'I69.4%' THEN 1 -- Paraplegia
        WHEN dd.icd_code LIKE 'J96.1%' THEN 1 -- Chronic lung disease
        WHEN dd.icd_code LIKE 'A41.0%' OR dd.icd_code LIKE 'R65.2%' THEN 1 -- Metastatic cancer
        WHEN dd.icd_code LIKE 'B20%' OR dd.icd_code LIKE 'B21%' OR dd.icd_code LIKE 'B22%' OR dd.icd_code LIKE 'B24%' THEN 1 -- HIV
        ELSE 0
      END
    ) AS cci_score
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    c.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY
    d.hadm_id
),

-- Complications
complications AS (
  SELECT
    d.hadm_id,
    MAX(CASE WHEN dd.icd_code LIKE 'I21%' OR dd.icd_code LIKE 'I22%' OR dd.icd_code LIKE 'I25.2%' THEN 1 ELSE 0 END) AS cardiovascular,
    MAX(CASE WHEN dd.icd_code LIKE 'I60%' OR dd.icd_code LIKE 'I61%' OR dd.icd_code LIKE 'I63%' OR dd.icd_code LIKE 'I64%' THEN 1 ELSE 0 END) AS neurologic
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  ON
    c.hadm_id = d.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
  ON
    d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY
    d.hadm_id
),

-- Combine all
final_data AS (
  SELECT
    c.hadm_id,
    c.hospital_expire_flag,
    COALESCE(cci.cci_score, 0) AS cci_score,
    COALESCE(comp.cardiovascular, 0) AS cardiovascular,
    COALESCE(comp.neurologic, 0) AS neurologic
  FROM
    cohort c
  LEFT JOIN
    cci_scores cci
  ON
    c.hadm_id = cci.hadm_id
  LEFT JOIN
    complications comp
  ON
    c.hadm_id = comp.hadm_id
),

quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY cci_score) AS cci_quartile
  FROM
    final_data
)

SELECT
  cci_quartile,
  COUNT(*) AS patient_count,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(cardiovascular) AS cardiovascular_rate,
  AVG(neurologic) AS neurologic_rate
FROM
  quartiles
GROUP BY
  cci_quartile
ORDER BY
  cci_quartile;