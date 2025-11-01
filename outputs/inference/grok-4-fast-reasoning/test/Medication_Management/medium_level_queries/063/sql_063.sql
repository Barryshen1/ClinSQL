WITH cohort AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 45 AND 55
    AND a.hospital_expire_flag = 0
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '250.%') OR
          (di.icd_version = 10 AND di.icd_code LIKE 'E1[0-4]%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` hf
      WHERE hf.subject_id = a.subject_id
        AND hf.hadm_id = a.hadm_id
        AND (
          (hf.icd_version = 9 AND hf.icd_code LIKE '428%') OR
          (hf.icd_version = 10 AND hf.icd_code LIKE 'I50%')
        )
    )
),
total_cohort AS (
  SELECT COUNT(*) AS n FROM cohort
),
first12_insulin AS (
  SELECT COUNT(DISTINCT pr.hadm_id) AS ct
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort c ON pr.subject_id = c.subject_id AND pr.hadm_id = c.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.drug IS NOT NULL
    AND UPPER(pr.drug) LIKE '%INSULIN%'
    AND pr.starttime >= c.admittime
    AND pr.starttime < c.admittime + INTERVAL 12 HOUR
),
final72_insulin AS (
  SELECT COUNT(DISTINCT pr.hadm_id) AS ct
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort c ON pr.subject_id = c.subject_id AND pr.hadm_id = c.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.drug IS NOT NULL
    AND UPPER(pr.drug) LIKE '%INSULIN%'
    AND pr.starttime >= c.admittime
    AND pr.starttime >= c.dischtime - INTERVAL 72 HOUR
    AND pr.starttime < c.dischtime
),
first12_oral AS (
  SELECT COUNT(DISTINCT pr.hadm_id) AS ct
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort c ON pr.subject_id = c.subject_id AND pr.hadm_id = c.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.drug IS NOT NULL
    AND (
      UPPER(pr.drug) LIKE '%METFORMIN%' OR
      UPPER(pr.drug) LIKE '%GLIPIZIDE%' OR
      UPPER(pr.drug) LIKE '%GLYBURIDE%' OR UPPER(pr.drug) LIKE '%GLIBENCLAMIDE%' OR
      UPPER(pr.drug) LIKE '%GLIMEPIRIDE%' OR
      UPPER(pr.drug) LIKE '%PIOGLITAZONE%' OR
      UPPER(pr.drug) LIKE '%ROSIGLITAZONE%' OR
      UPPER(pr.drug) LIKE '%SITAGLIPTIN%' OR
      UPPER(pr.drug) LIKE '%SAXAGLIPTIN%' OR
      UPPER(pr.drug) LIKE '%LINAGLIPTIN%' OR
      UPPER(pr.drug) LIKE '%CANAGLIFLOZIN%' OR
      UPPER(pr.drug) LIKE '%DAPAGLIFLOZIN%' OR
      UPPER(pr.drug) LIKE '%EMPAGLIFLOZIN%' OR
      UPPER(pr.drug) LIKE '%ACARBOSE%' OR
      UPPER(pr.drug) LIKE '%MIGLITOL%' OR
      UPPER(pr.drug) LIKE '%REPAGLINIDE%' OR
      UPPER(pr.drug) LIKE '%NATEGLINIDE%'
    )
    AND pr.starttime >= c.admittime
    AND pr.starttime < c.admittime + INTERVAL 12 HOUR
),
final72_oral AS (
  SELECT COUNT(DISTINCT pr.hadm_id) AS ct
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN cohort c ON pr.subject_id = c.subject_id AND pr.hadm_id = c.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.drug IS NOT NULL
    AND (
      UPPER(pr.drug) LIKE '%METFORMIN%' OR
      UPPER(pr.drug) LIKE '%GLIPIZIDE%' OR
      UPPER(pr.drug) LIKE '%GLYBURIDE%' OR UPPER(pr.drug) LIKE '%GLIBENCLAMIDE%' OR
      UPPER(pr.drug) LIKE '%GLIMEPIRIDE%' OR
      UPPER(pr.drug) LIKE '%PIOGLITAZONE%' OR
      UPPER(pr.drug) LIKE '%ROSIGLITAZONE%' OR
      UPPER(pr.drug) LIKE '%SITAGLIPTIN%' OR
      UPPER(pr.drug) LIKE '%SAXAGLIPTIN%' OR
      UPPER(pr.drug) LIKE '%LINAGLIPTIN%' OR
      UPPER(pr.drug) LIKE '%CANAGLIFLOZIN%' OR
      UPPER(pr.drug) LIKE '%DAPAGLIFLOZIN%' OR
      UPPER(pr.drug) LIKE '%EMPAGLIFLOZIN%' OR
      UPPER(pr.drug) LIKE '%ACARBOSE%' OR
      UPPER(pr.drug) LIKE '%MIGLITOL%' OR
      UPPER(pr.drug) LIKE '%REPAGLINIDE%' OR
      UPPER(pr.drug) LIKE '%NATEGLINIDE%'
    )
    AND pr.starttime >= c.admittime
    AND pr.starttime >= c.dischtime - INTERVAL 72 HOUR
    AND pr.starttime < c.dischtime
)
SELECT
  ROUND((fi.ct / tc.n) * 100, 2) AS insulin_first_12h_pct,
  ROUND((fii.ct / tc.n) * 100, 2) AS insulin_final_72h_pct,
  ROUND(((fi.ct / tc.n) * 100 - (fii.ct / tc.n) * 100), 2) AS insulin_pp_diff,
  ROUND((fo.ct / tc.n) * 100, 2) AS oral_first_12h_pct,
  ROUND((foo.ct / tc.n) * 100, 2) AS oral_final_72h_pct,
  ROUND(((fo.ct / tc.n) * 100 - (foo.ct / tc.n) * 100), 2) AS oral_pp_diff
FROM total_cohort tc
CROSS JOIN first12_insulin fi
CROSS JOIN final72_insulin fii
CROSS JOIN first12_oral fo
CROSS JOIN final72_oral foo;