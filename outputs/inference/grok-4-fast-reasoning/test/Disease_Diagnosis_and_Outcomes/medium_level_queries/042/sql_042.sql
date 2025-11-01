WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.anchor_age,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND CAST(p.anchor_age AS INT64) BETWEEN 69 AND 79
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410%') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
        )
    )
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id 
        AND di.hadm_id = a.hadm_id
        AND (
          -- Shock
          (di.icd_version = 9 AND di.icd_code LIKE '7855%') 
          OR (di.icd_version = 10 AND di.icd_code LIKE 'R57%')
          OR
          -- Respiratory failure
          (di.icd_version = 9 AND di.icd_code IN ('51881', '51882', '51884', '7991'))
          OR (di.icd_version = 10 AND di.icd_code LIKE 'J96%')
        )
    )
),
by_los AS (
  SELECT 
    CASE 
      WHEN los BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE '>=8 days'
    END AS los_group,
    COUNT(*) AS num_patients,
    SUM(CAST(hospital_expire_flag AS INT64)) AS num_deaths,
    ROUND(SUM(CAST(hospital_expire_flag AS INT64)) * 100.0 / COUNT(*), 2) AS mortality_pct
  FROM cohort
  GROUP BY los_group
),
overall_stats AS (
  SELECT 
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los
  FROM cohort
),
mortality_with_median AS (
  SELECT 
    bl.*,
    os.median_los
  FROM by_los bl
  CROSS JOIN overall_stats os
),
discharge_dest AS (
  SELECT 
    discharge_location,
    COUNT(*) AS num_discharges,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct
  FROM cohort
  GROUP BY discharge_location
)
SELECT 
  'Mortality by LOS' AS section,
  los_group,
  num_patients AS n,
  num_deaths,
  mortality_pct,
  median_los
FROM mortality_with_median

UNION ALL

SELECT 
  'Discharge Destination' AS section,
  discharge_location AS los_group,
  num_discharges AS n,
  NULL AS num_deaths,
  pct AS mortality_pct,
  NULL AS median_los
FROM discharge_dest

ORDER BY 
  section,
  CASE 
    WHEN section = 'Mortality by LOS' THEN 
      CASE los_group
        WHEN '1-3 days' THEN 1
        WHEN '4-7 days' THEN 2
        ELSE 3
      END 
    ELSE num_discharges 
  END DESC;