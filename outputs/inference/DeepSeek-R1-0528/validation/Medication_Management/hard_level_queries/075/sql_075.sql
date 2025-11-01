WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE 
        di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code IN ('491%', '492%', '493.2%', '496%'))
          OR 
          (di.icd_version = 10 AND di.icd_code LIKE 'J44%')
        )
    )
),
cohort_filtered AS (
  SELECT *
  FROM cohort
  WHERE age_admit BETWEEN 58 AND 68
),
meds AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT e.medication) AS complexity_score
  FROM cohort_filtered c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` e
    ON c.hadm_id = e.hadm_id
    AND e.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
  GROUP BY c.hadm_id
),
readmission_flag AS (
  SELECT 
    c.hadm_id,
    CASE WHEN MIN(a.admittime) IS NOT NULL THEN 1 ELSE 0 END AS readmit_30d
  FROM cohort_filtered c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id
    AND a.admittime > c.dischtime
    AND a.admittime <= DATETIME_ADD(c.dischtime, INTERVAL 30 DAY)
  GROUP BY c.hadm_id
),
combined AS (
  SELECT 
    c.hadm_id,
    c.hospital_expire_flag,
    COALESCE(m.complexity_score, 0) AS complexity_score,
    r.readmit_30d,
    DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM cohort_filtered c
  LEFT JOIN meds m ON c.hadm_id = m.hadm_id
  LEFT JOIN readmission_flag r ON c.hadm_id = r.hadm_id
),
with_tertiles AS (
  SELECT *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM combined
)
SELECT 
  tertile,
  COUNT(hadm_id) AS n,
  MIN(complexity_score) AS min_complexity,
  MAX(complexity_score) AS max_complexity,
  AVG(complexity_score) AS mean_complexity,
  AVG(los_days) AS mean_los,
  AVG(hospital_expire_flag) * 100 AS mortality_pct,
  AVG(readmit_30d) * 100 AS readmit_30d_pct
FROM with_tertiles
GROUP BY tertile
ORDER BY tertile;