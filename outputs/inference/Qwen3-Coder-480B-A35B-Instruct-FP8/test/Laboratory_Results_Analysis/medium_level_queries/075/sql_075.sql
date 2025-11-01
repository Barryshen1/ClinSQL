WITH primary_diagnosis AS (
  SELECT
    d.subject_id,
    d.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE
    d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'I21%') OR
      (d.icd_version = 9 AND d.icd_code = '786.59') OR
      (d.icd_version = 10 AND d.icd_code = 'R07.9')
    )
),
troponin_first AS (
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valuenum IS NOT NULL
),
troponin_cleaned AS (
  SELECT
    hadm_id,
    troponin_value
  FROM
    troponin_first
  WHERE
    rn = 1
),
patients_filtered AS (
  SELECT
    a.hadm_id,
    p.gender,
    p.anchor_age
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    primary_diagnosis pd
    ON a.hadm_id = pd.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
),
combined_data AS (
  SELECT
    pf.hadm_id,
    pf.anchor_age,
    t.troponin_value,
    CASE
      WHEN t.troponin_value <= 0.01 THEN 'Normal'
      WHEN t.troponin_value <= 0.039 THEN 'Borderline'
      ELSE 'Elevated'
    END AS troponin_category
  FROM
    patients_filtered pf
  JOIN
    troponin_cleaned t
    ON pf.hadm_id = t.hadm_id
)
SELECT
  troponin_category,
  COUNT(*) AS patient_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(troponin_value), 4) AS mean_troponin,
  ROUND(APPROX_QUANTILES(troponin_value, 2)[OFFSET(1)], 4) AS median_troponin,
  ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)], 4) AS q1_troponin,
  ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)], 4) AS q3_troponin,
  ROUND(APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)] - APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)], 4) AS iqr_troponin
FROM
  combined_data
GROUP BY
  troponin_category
ORDER BY
  CASE troponin_category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
  END;