WITH eligible AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE (
      LOWER(p.gender) = 'female' OR p.gender = 'F' OR p.gender = 'f'
    )
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.dischtime IS NOT NULL
),
diabetes_hf AS (
  SELECT e.hadm_id
  FROM eligible AS e
  WHERE EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      WHERE d.hadm_id = e.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250%') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'E11%')
        )
  )
  AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d2
      WHERE d2.hadm_id = e.hadm_id
        AND (
          (d2.icd_version = 9 AND d2.icd_code LIKE '428%') OR
          (d2.icd_version = 10 AND d2.icd_code LIKE 'I50%')
        )
  )
),
glp1_presence AS (
  SELECT e.hadm_id,
         EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
           WHERE pr.hadm_id = e.hadm_id
             AND (
               LOWER(pr.drug) LIKE '%liraglutide%' OR
               LOWER(pr.drug) LIKE '%exenatide%' OR
               LOWER(pr.drug) LIKE '%dulaglutide%' OR
               LOWER(pr.drug) LIKE '%semaglutide%' OR
               LOWER(pr.drug) LIKE '%lixisenatide%' OR
               LOWER(pr.drug) LIKE '%albiglutide%'
             )
             AND LOWER(pr.route) IN ('sc', 'subcutaneous', 'subcutaneous injection')
             AND pr.starttime BETWEEN e.admittime AND TIMESTAMP_ADD(e.admittime, INTERVAL 24 HOUR)
         ) AS first24,
         EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
           WHERE pr.hadm_id = e.hadm_id
             AND (
               LOWER(pr.drug) LIKE '%liraglutide%' OR
               LOWER(pr.drug) LIKE '%exenatide%' OR
               LOWER(pr.drug) LIKE '%dulaglutide%' OR
               LOWER(pr.drug) LIKE '%semaglutide%' OR
               LOWER(pr.drug) LIKE '%lixisenatide%' OR
               LOWER(pr.drug) LIKE '%albiglutide%'
             )
             AND LOWER(pr.route) IN ('sc', 'subcutaneous', 'subcutaneous injection')
             AND pr.starttime BETWEEN TIMESTAMP_SUB(e.dischtime, INTERVAL 12 HOUR) AND e.dischtime
         ) AS final12
  FROM eligible e
  JOIN diabetes_hf df ON df.hadm_id = e.hadm_id
)
SELECT
  COUNT(*) AS total_admissions,
  SUM(CASE WHEN first24 THEN 1 ELSE 0 END) AS n_first24,
  SUM(CASE WHEN final12 THEN 1 ELSE 0 END) AS n_final12,
  SAFE_DIVIDE(SUM(CASE WHEN first24 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS prevalence_first24_pct,
  SAFE_DIVIDE(SUM(CASE WHEN final12 THEN 1 ELSE 0 END), COUNT(*)) * 100 AS prevalence_final12_pct
FROM glp1_presence;