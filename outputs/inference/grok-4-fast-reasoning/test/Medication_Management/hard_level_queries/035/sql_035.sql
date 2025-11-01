WITH cohort AS (
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = a.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code = '288.50') 
          OR (d.icd_version = 10 AND d.icd_code LIKE 'D70%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
      WHERE d2.subject_id = a.subject_id 
        AND d2.hadm_id = a.hadm_id
        AND (
          (d2.icd_version = 9 AND d2.icd_code = '780.6') 
          OR (d2.icd_version = 10 AND d2.icd_code LIKE 'R50%')
        )
    )
),
scores AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
    COUNT(DISTINCT pres.drug) AS med_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres
    ON c.subject_id = pres.subject_id 
    AND c.hadm_id = pres.hadm_id
    AND pres.drug IS NOT NULL 
    AND pres.drug != ''
    AND pres.starttime >= c.admittime
    AND pres.starttime < TIMESTAMP_ADD(c.admittime, INTERVAL 2 DAY)
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
next_admission AS (
  SELECT 
    s.subject_id,
    s.hadm_id,
    MIN(a.admittime) AS next_admittime
  FROM scores s
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON s.subject_id = a.subject_id
    AND a.hadm_id != s.hadm_id
    AND a.admittime > s.dischtime
  GROUP BY s.subject_id, s.hadm_id
),
stratified AS (
  SELECT 
    s.*,
    COALESCE(
      CASE 
        WHEN na.next_admittime <= TIMESTAMP_ADD(s.dischtime, INTERVAL 30 DAY) 
        THEN 1 
        ELSE 0 
      END, 0
    ) AS readmitted_flag,
    NTILE(4) OVER (ORDER BY s.med_score ASC) AS quartile
  FROM scores s
  LEFT JOIN next_admission na
    ON s.hadm_id = na.hadm_id
)
SELECT 
  quartile,
  COUNT(*) AS patient_count,
  AVG(med_score) AS mean_score,
  MIN(med_score) AS min_score,
  MAX(med_score) AS max_score,
  AVG(los_days) AS mean_los_days,
  AVG(CAST(hospital_expire_flag AS FLOAT64) * 100) AS mortality_pct,
  AVG(CAST(readmitted_flag AS FLOAT64) * 100) AS readmission_30d_pct
FROM stratified
GROUP BY quartile
ORDER BY quartile;