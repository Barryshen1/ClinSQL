WITH target_cohort AS (
  -- Inpatients: female, age 44-54
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
t2dm_adm AS (
  -- Admissions with type 2 diabetes mellitus
  SELECT DISTINCT tc.subject_id, tc.hadm_id
  FROM target_cohort tc
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON tc.subject_id = di.subject_id AND tc.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%diabetes%' AND LOWER(d.long_title) LIKE '%type 2%'
),
hf_adm AS (
  -- Admissions with heart failure
  SELECT DISTINCT tc.subject_id, tc.hadm_id
  FROM target_cohort tc
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON tc.subject_id = di.subject_id AND tc.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%heart failure%'
),
cohort_final AS (
  -- Admissions with both T2DM and HF
  SELECT tc.subject_id, tc.hadm_id, tc.admittime, tc.dischtime
  FROM target_cohort tc
  JOIN t2dm_adm t ON tc.subject_id = t.subject_id AND tc.hadm_id = t.hadm_id
  JOIN hf_adm h ON tc.subject_id = h.subject_id AND tc.hadm_id = h.hadm_id
),
therapy_flags AS (
  -- For each admission, determine insulin/oral exposure in first 24h and last 48h
  SELECT cf.subject_id, cf.hadm_id, cf.admittime, cf.dischtime,
         -- Insulin in first 24h
         CASE WHEN EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
           WHERE pr.subject_id = cf.subject_id
             AND pr.hadm_id = cf.hadm_id
             AND pr.drug IS NOT NULL
             AND LOWER(pr.drug) LIKE '%insulin%'
             AND pr.starttime < TIMESTAMP_ADD(cf.admittime, INTERVAL 24 HOUR)
             AND pr.stoptime > cf.admittime
         ) THEN 1 ELSE 0 END AS insulin_first,
         -- Oral antidiabetic in first 24h
         CASE WHEN EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
           WHERE pr.subject_id = cf.subject_id
             AND pr.hadm_id = cf.hadm_id
             AND pr.drug IS NOT NULL
             AND REGEXP_CONTAINS(LOWER(pr.drug), r'(metformin|glyburide|glipizide|glimepiride|pioglitazone|rosiglitazone|acarbose|repaglinide|nateglinide|sitagliptin|linagliptin|empagliflozin|dapagliflozin|canagliflozin)')
             AND pr.starttime < TIMESTAMP_ADD(cf.admittime, INTERVAL 24 HOUR)
             AND pr.stoptime > cf.admittime
         ) THEN 1 ELSE 0 END AS oral_first,
         -- Insulin in last 48h
         CASE WHEN EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
           WHERE pr.subject_id = cf.subject_id
             AND pr.hadm_id = cf.hadm_id
             AND pr.drug IS NOT NULL
             AND LOWER(pr.drug) LIKE '%insulin%'
             AND pr.starttime < cf.dischtime
             AND pr.stoptime > TIMESTAMP_SUB(cf.dischtime, INTERVAL 48 HOUR)
         ) THEN 1 ELSE 0 END AS insulin_last,
         -- Oral antidiabetic in last 48h
         CASE WHEN EXISTS (
           SELECT 1
           FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
           WHERE pr.subject_id = cf.subject_id
             AND pr.hadm_id = cf.hadm_id
             AND pr.drug IS NOT NULL
             AND REGEXP_CONTAINS(LOWER(pr.drug), r'(metformin|glyburide|glipizide|glimepiride|pioglitazone|rosiglitazone|acarbose|repaglinide|nateglinide|sitagliptin|linagliptin|empagliflozin|dapagliflozin|canagliflozin)')
             AND pr.starttime < cf.dischtime
             AND pr.stoptime > TIMESTAMP_SUB(cf.dischtime, INTERVAL 48 HOUR)
         ) THEN 1 ELSE 0 END AS oral_last
  FROM cohort_final cf
)
SELECT
  COUNT(*) AS n_admissions,
  SUM(insulin_first) AS first24_insulin_present,
  SUM(oral_first) AS first24_oral_present,
  SUM(insulin_last) AS last48_insulin_present,
  SUM(oral_last) AS last48_oral_present,
  SUM(CASE WHEN insulin_first = 1 AND insulin_last = 1 THEN 1 ELSE 0 END) AS insulin_continued,
  SUM(CASE WHEN insulin_first = 0 AND insulin_last = 1 THEN 1 ELSE 0 END) AS insulin_initiated,
  SUM(CASE WHEN insulin_first = 1 AND insulin_last = 0 THEN 1 ELSE 0 END) AS insulin_discontinued,
  SUM(CASE WHEN oral_first = 1 AND oral_last = 1 THEN 1 ELSE 0 END) AS oral_continued,
  SUM(CASE WHEN oral_first = 0 AND oral_last = 1 THEN 1 ELSE 0 END) AS oral_initiated,
  SUM(CASE WHEN oral_first = 1 AND oral_last = 0 THEN 1 ELSE 0 END) AS oral_discontinued,
  SAFE_DIVIDE(SUM(insulin_first), COUNT(*)) * 100 AS first24_insulin_prev_pct,
  SAFE_DIVIDE(SUM(oral_first), COUNT(*)) * 100 AS first24_oral_prev_pct,
  SAFE_DIVIDE(SUM(insulin_last), COUNT(*)) * 100 AS last48_insulin_prev_pct,
  SAFE_DIVIDE(SUM(oral_last), COUNT(*)) * 100 AS last48_oral_prev_pct
FROM therapy_flags;