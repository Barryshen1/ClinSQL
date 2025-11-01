WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    a.admission_type,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 44 AND 54
    AND a.admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) > 0
    AND a.hadm_id NOT IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` 
      WHERE hadm_id IS NOT NULL
    )
)
SELECT 
  stratum,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
  AVG(CASE WHEN los <= 7 THEN 1.0 ELSE 0 END) * 100 AS perc_le_7
FROM (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 THEN 'death'
      WHEN REGEXP_CONTAINS(discharge_location, r'Hospice') THEN 'hospice'
      WHEN discharge_location LIKE '%Home%' 
        AND NOT REGEXP_CONTAINS(discharge_location, r'Hospice') THEN 'home'
      ELSE 'other'
    END AS stratum
  FROM cohort
)
WHERE 
  stratum IN ('home', 'hospice', 'death')
GROUP BY 
  stratum
HAVING 
  COUNT(*) > 0
ORDER BY 
  stratum;