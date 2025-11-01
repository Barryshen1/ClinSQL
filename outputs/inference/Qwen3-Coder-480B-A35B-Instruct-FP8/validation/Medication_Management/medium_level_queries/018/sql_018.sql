WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON icu.hadm_id = adm.hadm_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
      WHERE dx.hadm_id = adm.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250.%') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
      WHERE dx.hadm_id = adm.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428.%') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),

drug_prescriptions AS (
  SELECT
    c.hadm_id,
    c.stay_id,
    c.intime,
    c.outtime,
    p.drug,
    p.starttime,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' THEN 'DPP4'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' THEN 'SGLT2'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE
    p.starttime >= c.intime
    AND p.starttime <= c.outtime
),

time_window_flags AS (
  SELECT
    hadm_id,
    stay_id,
    drug_class,
    starttime,
    intime,
    outtime,
    CASE WHEN starttime <= intime + INTERVAL 72 HOUR THEN 1 ELSE 0 END AS in_first_72h,
    CASE WHEN starttime >= outtime - INTERVAL 48 HOUR THEN 1 ELSE 0 END AS in_final_48h
  FROM
    drug_prescriptions
  WHERE
    drug_class IS NOT NULL
),

window_counts AS (
  SELECT
    drug_class,
    SUM(in_first_72h) AS count_first_72h,
    SUM(in_final_48h) AS count_final_48h,
    COUNT(DISTINCT CASE WHEN in_first_72h = 1 THEN hadm_id END) AS total_first_72h,
    COUNT(DISTINCT CASE WHEN in_final_48h = 1 THEN hadm_id END) AS total_final_48h
  FROM
    time_window_flags
  GROUP BY
    drug_class
)

SELECT
  drug_class,
  ROUND(SAFE_DIVIDE(count_first_72h, total_first_72h) * 100, 2) AS prevalence_first_72h_pct,
  ROUND(SAFE_DIVIDE(count_final_48h, total_final_48h) * 100, 2) AS prevalence_final_48h_pct,
  ROUND(
    (SAFE_DIVIDE(count_final_48h, total_final_48h) - SAFE_DIVIDE(count_first_72h, total_first_72h)) * 100,
    2
  ) AS abs_diff_pct
FROM
  window_counts
ORDER BY
  drug_class;