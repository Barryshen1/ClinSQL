WITH base_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE 
        d.hadm_id = a.hadm_id AND 
        ((d.icd_version = 9 AND d.icd_code LIKE '410%') OR 
         (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%')))
    )
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 67 AND 77
),

med_score AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT e.medication) AS complexity_score
  FROM base_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
    AND e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.hadm_id
),

cohort_with_next_adm AS (
  SELECT 
    c.*,
    LEAD(a.admittime) OVER (PARTITION BY c.subject_id ORDER BY a.admittime) AS next_admittime
  FROM base_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id
),

cohort_with_metrics AS (
  SELECT 
    c.*,
    COALESCE(m.complexity_score, 0) AS complexity_score,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days,
    c.hospital_expire_flag AS mortality_flag,
    CASE 
      WHEN c.hospital_expire_flag = 1 THEN 0
      WHEN DATETIME_DIFF(c.next_admittime, c.dischtime, DAY) <= 30 THEN 1
      ELSE 0 
    END AS readmission_flag
  FROM cohort_with_next_adm c
  LEFT JOIN med_score m
    ON c.hadm_id = m.hadm_id
),

tertile_groups AS (
  SELECT 
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM cohort_with_metrics
)

SELECT 
  tertile,
  COUNT(hadm_id) AS admission_count,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  ROUND(AVG(complexity_score), 2) AS mean_score,
  ROUND(AVG(los_days), 2) AS mean_los_days,
  ROUND(AVG(mortality_flag) * 100, 2) AS mortality_percent,
  ROUND(AVG(readmission_flag) * 100, 2) AS readmission_percent
FROM tertile_groups
GROUP BY tertile
ORDER BY tertile;