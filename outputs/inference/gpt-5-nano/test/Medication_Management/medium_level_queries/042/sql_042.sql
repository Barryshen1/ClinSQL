WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 51 AND 61
),
diagnoses_flags AS (
  SELECT
    di.hadm_id,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%diabetes%' THEN 1 ELSE 0 END) AS has_diabetes,
    MAX(CASE WHEN LOWER(dd.long_title) LIKE '%heart failure%' 
              OR LOWER(dd.long_title) LIKE '%congestive heart failure%' THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS dd
    ON di.icd_code = dd.icd_code
   AND di.icd_version = dd.icd_version
  GROUP BY di.hadm_id
),
cohort_filtered AS (
  SELECT c.subject_id, c.hadm_id, c.admittime, c.dischtime
  FROM cohort AS c
  JOIN diagnoses_flags AS df
    ON c.hadm_id = df.hadm_id
  WHERE df.has_diabetes = 1
    AND df.has_hf = 1
),
med_exposure AS (
  SELECT
    cf.subject_id,
    cf.hadm_id,
    cf.admittime,
    cf.dischtime,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = cf.subject_id
        AND pr.hadm_id = cf.hadm_id
        AND pr.starttime < TIMESTAMP_ADD(cf.admittime, INTERVAL 48 HOUR)
        AND (pr.stoptime IS NULL OR pr.stoptime > cf.admittime)
        AND LOWER(pr.drug) LIKE '%insulin%'
    ) THEN 1 ELSE 0 END AS insulin_first,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = cf.subject_id
        AND pr.hadm_id = cf.hadm_id
        AND pr.starttime < cf.dischtime
        AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(cf.dischtime, INTERVAL 24 HOUR))
        AND LOWER(pr.drug) LIKE '%insulin%'
    ) THEN 1 ELSE 0 END AS insulin_final,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = cf.subject_id
        AND pr.hadm_id = cf.hadm_id
        AND pr.starttime < TIMESTAMP_ADD(cf.admittime, INTERVAL 48 HOUR)
        AND (pr.stoptime IS NULL OR pr.stoptime > cf.admittime)
        AND (
          LOWER(pr.drug) LIKE '%metformin%'
          OR LOWER(pr.drug) LIKE '%glyburide%'
          OR LOWER(pr.drug) LIKE '%glipizide%'
          OR LOWER(pr.drug) LIKE '%glimepiride%'
          OR LOWER(pr.drug) LIKE '%pioglitazone%'
          OR LOWER(pr.drug) LIKE '%rosiglitazone%'
          OR LOWER(pr.drug) LIKE '%acarbose%'
          OR LOWER(pr.drug) LIKE '%miglitol%'
          OR LOWER(pr.drug) LIKE '%sitagliptin%'
          OR LOWER(pr.drug) LIKE '%linagliptin%'
        )
    ) THEN 1 ELSE 0 END AS oral_first,
    CASE WHEN EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` AS pr
      WHERE pr.subject_id = cf.subject_id
        AND pr.hadm_id = cf.hadm_id
        AND pr.starttime < cf.dischtime
        AND (pr.stoptime IS NULL OR pr.stoptime > TIMESTAMP_SUB(cf.dischtime, INTERVAL 24 HOUR))
        AND (
          LOWER(pr.drug) LIKE '%metformin%'
          OR LOWER(pr.drug) LIKE '%glyburide%'
          OR LOWER(pr.drug) LIKE '%glipizide%'
          OR LOWER(pr.drug) LIKE '%glimepiride%'
          OR LOWER(pr.drug) LIKE '%pioglitazone%'
          OR LOWER(pr.drug) LIKE '%rosiglitazone%'
          OR LOWER(pr.drug) LIKE '%acarbose%'
          OR LOWER(pr.drug) LIKE '%miglitol%'
          OR LOWER(pr.drug) LIKE '%sitagliptin%'
          OR LOWER(pr.drug) LIKE '%linagliptin%'
        )
    ) THEN 1 ELSE 0 END AS oral_final
  FROM cohort_filtered cf
)

SELECT
  COUNT(*) AS cohort_size,
  SUM(insulin_first) AS insulin_first_count,
  ROUND(SUM(insulin_first) * 100.0 / COUNT(*), 2) AS insulin_first_pct,
  SUM(oral_first) AS oral_first_count,
  ROUND(SUM(oral_first) * 100.0 / COUNT(*), 2) AS oral_first_pct,
  SUM(insulin_final) AS insulin_final_count,
  ROUND(SUM(insulin_final) * 100.0 / COUNT(*), 2) AS insulin_final_pct,
  SUM(oral_final) AS oral_final_count,
  ROUND(SUM(oral_final) * 100.0 / COUNT(*), 2) AS oral_final_pct,
  SUM(CASE WHEN insulin_first = 1 AND insulin_final = 1 THEN 1 ELSE 0 END) AS insulin_continued,
  SUM(CASE WHEN insulin_first = 0 AND insulin_final = 1 THEN 1 ELSE 0 END) AS insulin_initiated,
  SUM(CASE WHEN insulin_first = 1 AND insulin_final = 0 THEN 1 ELSE 0 END) AS insulin_discontinued,
  SUM(CASE WHEN oral_first = 1 AND oral_final = 1 THEN 1 ELSE 0 END) AS oral_continued,
  SUM(CASE WHEN oral_first = 0 AND oral_final = 1 THEN 1 ELSE 0 END) AS oral_initiated,
  SUM(CASE WHEN oral_first = 1 AND oral_final = 0 THEN 1 ELSE 0 END) AS oral_discontinued
FROM med_exposure;