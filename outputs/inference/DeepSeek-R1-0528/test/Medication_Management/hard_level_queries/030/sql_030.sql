WITH cohort AS (
  SELECT DISTINCT
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON a.hadm_id = diag.hadm_id
    AND a.subject_id = diag.subject_id
  WHERE 
    p.gender = 'F'
    AND (
      (diag.icd_version = 9 AND diag.icd_code = '5770') 
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'K85%')
    )
), filtered_cohort AS (
  SELECT *
  FROM cohort
  WHERE age_at_admission BETWEEN 71 AND 81
), medication_counts AS (
  SELECT 
    fc.hadm_id,
    COUNT(DISTINCT e.medication) AS med_count
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON fc.hadm_id = e.hadm_id
    AND e.charttime >= fc.admittime
    AND e.charttime < DATETIME_ADD(fc.admittime, INTERVAL 72 HOUR)
  GROUP BY fc.hadm_id
), cohort_with_tertiles AS (
  SELECT 
    fc.*,
    COALESCE(mc.med_count, 0) AS med_count,
    NTILE(3) OVER (ORDER BY COALESCE(mc.med_count, 0)) AS tertile
  FROM filtered_cohort fc
  LEFT JOIN medication_counts mc
    ON fc.hadm_id = mc.hadm_id
), readmission_flags AS (
  SELECT 
    c.*,
    CASE 
      WHEN c.hospital_expire_flag = 0 
           AND ra.readmission_time IS NOT NULL 
           THEN 1 
      WHEN c.hospital_expire_flag = 0 
           THEN 0 
      ELSE NULL 
    END AS readmission_flag
  FROM cohort_with_tertiles c
  LEFT JOIN (
    SELECT 
      a1.hadm_id,
      MIN(a2.admittime) AS readmission_time
    FROM cohort_with_tertiles a1
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
      ON a1.subject_id = a2.subject_id
      AND a2.admittime > a1.dischtime
      AND a2.admittime <= DATETIME_ADD(a1.dischtime, INTERVAL 30 DAY)
      AND a2.hadm_id != a1.hadm_id
    GROUP BY a1.hadm_id
  ) ra
    ON c.hadm_id = ra.hadm_id
)
SELECT 
  tertile,
  COUNT(*) AS n_admissions,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(readmission_flag) AS readmission_rate
FROM readmission_flags
GROUP BY tertile
ORDER BY tertile;