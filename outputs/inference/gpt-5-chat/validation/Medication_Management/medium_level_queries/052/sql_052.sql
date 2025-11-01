WITH cohort AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),
dx AS (
  SELECT hadm_id,
    MAX(CASE WHEN (di.icd_version = 10 AND di.icd_code LIKE 'E11%')
              OR (di.icd_version = 9 AND di.icd_code LIKE '250%') THEN 1 ELSE 0 END) AS has_t2dm,
    MAX(CASE WHEN (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
              OR (di.icd_version = 9 AND di.icd_code LIKE '428%') THEN 1 ELSE 0 END) AS has_hf
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  GROUP BY hadm_id
),
filtered_cohort AS (
  SELECT c.*
  FROM cohort c
  JOIN dx
    ON c.hadm_id = dx.hadm_id
  WHERE dx.has_t2dm = 1
    AND dx.has_hf = 1
),
meds AS (
  SELECT fc.subject_id, fc.hadm_id,
         pr.starttime,
         UPPER(pr.drug) AS drug
  FROM filtered_cohort fc
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON fc.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
),
classified AS (
  SELECT m.*,
         CASE WHEN drug LIKE '%INSULIN%' THEN 'INSULIN'
              ELSE 'ORAL'
         END AS drug_class
  FROM meds m
),
first48 AS (
  SELECT drug_class, COUNT(*) AS cnt
  FROM classified m
  JOIN filtered_cohort fc USING(hadm_id)
  WHERE m.starttime BETWEEN fc.admittime AND TIMESTAMP_ADD(fc.admittime, INTERVAL 48 HOUR)
  GROUP BY drug_class
),
final24 AS (
  SELECT drug_class, COUNT(*) AS cnt
  FROM classified m
  JOIN filtered_cohort fc USING(hadm_id)
  WHERE m.starttime BETWEEN TIMESTAMP_SUB(fc.dischtime, INTERVAL 24 HOUR) AND fc.dischtime
  GROUP BY drug_class
),
pct AS (
  SELECT 
    SAFE_DIVIDE(SUM(CASE WHEN drug_class='INSULIN' THEN cnt ELSE 0 END), SUM(cnt))*100 AS first48_insulin_pct,
    SAFE_DIVIDE(SUM(CASE WHEN drug_class='ORAL' THEN cnt ELSE 0 END), SUM(cnt))*100 AS first48_oral_pct
  FROM first48
),
pct2 AS (
  SELECT 
    SAFE_DIVIDE(SUM(CASE WHEN drug_class='INSULIN' THEN cnt ELSE 0 END), SUM(cnt))*100 AS final24_insulin_pct,
    SAFE_DIVIDE(SUM(CASE WHEN drug_class='ORAL' THEN cnt ELSE 0 END), SUM(cnt))*100 AS final24_oral_pct
  FROM final24
)
SELECT p.first48_insulin_pct, p.first48_oral_pct, q.final24_insulin_pct, q.final24_oral_pct
FROM pct p CROSS JOIN pct2 q;