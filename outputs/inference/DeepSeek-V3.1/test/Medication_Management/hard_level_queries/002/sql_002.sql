WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Calculate age at admission: anchor_year is the year, and anchor_age is the age at that year.
    -- So approx DOB = anchor_year - anchor_age. Then age at admission = YEAR(admittime) - (anchor_year - anchor_age)
    -- But since admittime is a datetime, we extract year.
    EXTRACT(YEAR FROM adm.admittime) - (pat.anchor_year - pat.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        adm.subject_id = diag.subject_id 
        AND adm.hadm_id = diag.hadm_id
        AND (
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%') 
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I22%')
          OR (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
        )
    )
),

-- Calculate medication complexity score (count distinct drugs started in first 24h)
med_score AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT p.drug) AS score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
    AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),

-- Combine cohort with med score and filter age 67-77 at admission
cohort_with_score AS (
  SELECT 
    c.*,
    m.score,
    -- Filter by age_at_admission (calculated above) between 67 and 77
  FROM cohort c
  INNER JOIN med_score m
    ON c.hadm_id = m.hadm_id
  WHERE c.age_at_admission BETWEEN 67 AND 77
),

-- Assign tertiles
tertiles AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY score) AS tertile
  FROM cohort_with_score
),

-- Calculate 30-day readmission flag per admission
readmissions AS (
  SELECT 
    t1.hadm_id,
    CASE 
      WHEN MIN(t2.admittime) IS NOT NULL THEN 1 
      ELSE 0 
    END AS readmit_30d
  FROM tertiles t1
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` t2
    ON t1.subject_id = t2.subject_id
    AND t2.admittime > t1.dischtime
    AND t2.admittime <= DATETIME_ADD(t1.dischtime, INTERVAL 30 DAY)
  GROUP BY t1.hadm_id
)

-- Final aggregation per tertile
SELECT 
  tertile,
  COUNT(*) AS admission_count,
  MIN(score) AS score_min,
  MAX(score) AS score_max,
  ROUND(AVG(score), 2) AS score_mean,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(100 * AVG(hospital_expire_flag), 2) AS mortality_percent,
  ROUND(100 * AVG(readmit_30d), 2) AS readmit_30d_percent
FROM tertiles t
LEFT JOIN readmissions r
  ON t.hadm_id = r.hadm_id
GROUP BY tertile
ORDER BY tertile;