WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 87 AND 97
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '431') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I61%')
        )
    )
),
med_complexity AS (
  SELECT 
    c.hadm_id,
    COUNT(DISTINCT CONCAT(COALESCE(pres.drug, 'UNKNOWN'), '|', COALESCE(pres.route, 'UNKNOWN'))) AS med_complexity
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.hadm_id = pres.hadm_id
    AND pres.starttime >= c.admittime
    AND pres.starttime < c.admittime + INTERVAL 48 HOUR
  GROUP BY c.hadm_id
),
readmission AS (
  SELECT 
    c.*,
    LEAD(c.admittime) OVER (PARTITION BY c.subject_id ORDER BY c.admittime) AS next_admittime
  FROM cohort c
),
readmission_flag AS (
  SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 0 
        AND next_admittime IS NOT NULL 
        AND next_admittime <= dischtime + INTERVAL 30 DAY 
      THEN 1 
      ELSE 0 
    END AS readmission_30d
  FROM readmission
),
combined AS (
  SELECT 
    r.*,
    m.med_complexity,
    NTILE(4) OVER (ORDER BY m.med_complexity) AS quartile
  FROM readmission_flag r
  LEFT JOIN med_complexity m
    ON r.hadm_id = m.hadm_id
)
SELECT 
  quartile,
  COUNT(*) AS admissions,
  MIN(med_complexity) AS min_score,
  MAX(med_complexity) AS max_score,
  AVG(DATETIME_DIFF(dischtime, admittime, MINUTE) / 1440.0) AS avg_los_days,
  (SUM(hospital_expire_flag) * 100.0 / COUNT(*)) AS mortality_pct,
  (SUM(readmission_30d) * 100.0 / COUNT(CASE WHEN hospital_expire_flag = 0 THEN 1 END)) AS readmission_30d_pct
FROM combined
GROUP BY quartile
ORDER BY quartile;