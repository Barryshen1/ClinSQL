WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 87 AND 97
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE 
        di.hadm_id = a.hadm_id
        AND di.icd_version = '10'
        AND di.icd_code LIKE 'I61%'
    )
),

cohort_with_score AS (
  SELECT 
    c.*,
    (
      SELECT 
        COUNT(DISTINCT CONCAT(TRIM(e.medication), '|', COALESCE(TRIM(ed.route), 'NO_ROUTE')))
      FROM 
        `physionet-data.mimiciv_3_1_hosp.emar` e
      LEFT JOIN 
        `physionet-data.mimiciv_3_1_hosp.emar_detail` ed
      ON 
        e.emar_id = ed.emar_id 
        AND CAST(e.emar_seq AS INT64) = CAST(ed.emar_seq AS INT64)
      WHERE 
        e.hadm_id = c.hadm_id
        AND e.medication IS NOT NULL
        AND LENGTH(TRIM(e.medication)) > 0
        AND e.charttime >= c.admittime
        AND e.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    ) AS score
  FROM 
    cohort c
),

with_quartile AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY score ASC) AS quartile,
    EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE 
        a2.subject_id = cws.subject_id
        AND a2.hadm_id != cws.hadm_id
        AND a2.admittime > cws.dischtime
        AND a2.admittime <= TIMESTAMP_ADD(cws.dischtime, INTERVAL 30 DAY)
    ) AS has_readmission
  FROM 
    cohort_with_score cws
)

SELECT 
  quartile,
  COUNT(*) AS admissions,
  MIN(score) AS score_min,
  MAX(score) AS score_max,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) * 100, 2) AS mortality_pct,
  ROUND(AVG(CASE WHEN has_readmission THEN 1.0 ELSE 0.0 END) * 100, 2) AS readmission_30d_pct
FROM 
  with_quartile
GROUP BY 
  quartile
ORDER BY 
  quartile;