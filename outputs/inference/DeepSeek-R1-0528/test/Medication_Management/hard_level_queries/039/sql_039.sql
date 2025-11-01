WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        adm.hadm_id = diag.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code IN ('431', '4320', '4321', '4329'))
          OR 
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I60%')
          OR 
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I61%')
          OR 
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I62%')
        )
    )
),
filtered_cohort AS (
  SELECT 
    subject_id, 
    hadm_id, 
    admittime, 
    dischtime, 
    hospital_expire_flag
  FROM cohort
  WHERE 
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 87 AND 97
),
med_complexity AS (
  SELECT 
    fc.hadm_id,
    COUNT(DISTINCT CONCAT(ed.product_description, '|', ed.route)) AS complexity_score
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar` em
    ON fc.hadm_id = em.hadm_id
    AND em.charttime BETWEEN fc.admittime AND DATETIME_ADD(fc.admittime, INTERVAL 48 HOUR)
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
    ON em.emar_id = ed.emar_id 
    AND em.emar_seq = ed.emar_seq 
    AND em.subject_id = ed.subject_id
    AND ed.route IS NOT NULL
    AND ed.product_description IS NOT NULL
  GROUP BY fc.hadm_id
),
quartiles AS (
  SELECT 
    hadm_id,
    complexity_score,
    NTILE(4) OVER (ORDER BY complexity_score) AS quartile
  FROM med_complexity
),
readmission_flag AS (
  SELECT 
    fc.hadm_id,
    MAX(CASE WHEN DATE_DIFF(a2.admittime, fc.dischtime, DAY) BETWEEN 1 AND 30 THEN 1 ELSE 0 END) AS readmit_30d
  FROM filtered_cohort fc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON fc.subject_id = a2.subject_id
    AND a2.admittime > fc.dischtime
  GROUP BY fc.hadm_id
)
SELECT 
  q.quartile,
  COUNT(*) AS admissions,
  MIN(q.complexity_score) AS min_score,
  MAX(q.complexity_score) AS max_score,
  APPROX_QUANTILES(CAST(DATE_DIFF(fc.dischtime, fc.admittime, DAY) AS FLOAT64), 100)[OFFSET(25)] AS q1_los,
  APPROX_QUANTILES(CAST(DATE_DIFF(fc.dischtime, fc.admittime, DAY) AS FLOAT64), 100)[OFFSET(50)] AS median_los,
  APPROX_QUANTILES(CAST(DATE_DIFF(fc.dischtime, fc.admittime, DAY) AS FLOAT64), 100)[OFFSET(75)] AS q3_los,
  ROUND(AVG(fc.hospital_expire_flag) * 100, 2) AS mortality_percent,
  ROUND(AVG(rf.readmit_30d) * 100, 2) AS readmit_percent
FROM filtered_cohort fc
INNER JOIN med_complexity mc 
  ON fc.hadm_id = mc.hadm_id
INNER JOIN quartiles q 
  ON fc.hadm_id = q.hadm_id
INNER JOIN readmission_flag rf 
  ON fc.hadm_id = rf.hadm_id
GROUP BY q.quartile
ORDER BY q.quartile;