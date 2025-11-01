WITH base_cohort AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.dischtime IS NOT NULL
),

cohort_primary_diagnosis AS (
  SELECT 
    bc.*
  FROM base_cohort bc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON bc.hadm_id = diag.hadm_id
  WHERE diag.seq_num = 1
    AND (
      (diag.icd_version = 10 AND diag.icd_code = 'J44.1')
      OR (diag.icd_version = 9 AND diag.icd_code IN ('491.21', '491.22'))
    )
    AND bc.age BETWEEN 58 AND 68
),

complexity AS (
  SELECT 
    c.hadm_id,
    c.subject_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    COALESCE(COUNT(DISTINCT pr.drug), 0) AS complexity_score
  FROM cohort_primary_diagnosis c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime <= c.admittime + INTERVAL '72' HOUR
  GROUP BY 1, 2, 3, 4, 5
),

all_admissions AS (
  SELECT 
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
  WHERE dischtime IS NOT NULL
),

readmission_flags AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN next_admittime <= dischtime + INTERVAL '30' DAY THEN 1 
      ELSE 0 
    END AS readmitted_30d
  FROM all_admissions
),

cohort_with_readmission AS (
  SELECT 
    c.*,
    COALESCE(r.readmitted_30d, 0) AS readmitted_30d
  FROM complexity c
  LEFT JOIN readmission_flags r
    ON c.hadm_id = r.hadm_id
),

cohort_with_tertile AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM cohort_with_readmission
)

SELECT
  tertile,
  COUNT(*) AS n,
  MIN(complexity_score) AS min_complexity,
  MAX(complexity_score) AS max_complexity,
  AVG(complexity_score) AS mean_complexity,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS mean_los,
  (SUM(hospital_expire_flag) * 100.0) / COUNT(*) AS mortality_pct,
  (SUM(readmitted_30d) * 100.0) / COUNT(*) AS readmission_30d_pct
FROM cohort_with_tertile
GROUP BY tertile
ORDER BY tertile;