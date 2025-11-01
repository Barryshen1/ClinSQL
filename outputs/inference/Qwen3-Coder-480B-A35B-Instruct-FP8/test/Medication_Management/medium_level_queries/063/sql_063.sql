WITH cohort AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE LOWER(d.long_title) LIKE '%diabetes%'
    )
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE LOWER(d.long_title) LIKE '%heart failure%'
    )
),

meds_first_12h AS (
  SELECT DISTINCT
    c.hadm_id,
    CASE WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'insulin'
         WHEN LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glyburide%' THEN 'oral'
    END AS drug_class
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON c.hadm_id = pr.hadm_id
  WHERE
    pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
    AND (LOWER(pr.drug) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glyburide%')
),

meds_final_72h AS (
  SELECT DISTINCT
    c.hadm_id,
    CASE WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'insulin'
         WHEN LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glyburide%' THEN 'oral'
    END AS drug_class
  FROM
    cohort c
  JOIN
    physionet-data.mimiciv_3_1_hosp.prescriptions pr
    ON c.hadm_id = pr.hadm_id
  WHERE
    pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime
    AND (LOWER(pr.drug) LIKE '%insulin%' OR LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%glyburide%')
),

first_rates AS (
  SELECT
    drug_class,
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM cohort) AS pct
  FROM
    meds_first_12h
  GROUP BY
    drug_class
),

final_rates AS (
  SELECT
    drug_class,
    COUNT(*) * 100.0 / (SELECT COUNT(*) FROM cohort) AS pct
  FROM
    meds_final_72h
  GROUP BY
    drug_class
),

combined AS (
  SELECT
    COALESCE(f.drug_class, fi.drug_class) AS drug_class,
    COALESCE(f.pct, 0) AS first_pct,
    COALESCE(fi.pct, 0) AS final_pct,
    (COALESCE(f.pct, 0) - COALESCE(fi.pct, 0)) AS pp_diff
  FROM
    first_rates f
  FULL OUTER JOIN
    final_rates fi
    ON f.drug_class = fi.drug_class
)

SELECT
  drug_class,
  ROUND(first_pct, 2) AS first_12h_pct,
  ROUND(final_pct, 2) AS final_72h_pct,
  ROUND(pp_diff, 2) AS pointwise_diff
FROM
  combined
ORDER BY
  drug_class;