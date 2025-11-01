WITH eligible_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate birthdate from anchor_year and anchor_age
    DATE_SUB(
      DATE(p.anchor_year, 1, 1), 
      INTERVAL p.anchor_age YEAR
    ) AS birthdate,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'F'
    AND dd.icd_code LIKE 'I26.%'  -- PE codes
    AND dd.icd_version = 10  -- ICD-10
),
age_calculated AS (
  SELECT 
    *,
    TIMESTAMP_DIFF(admittime, birthdate, YEAR) AS age
  FROM eligible_admissions
),
filtered_age AS (
  SELECT *
  FROM age_calculated
  WHERE age BETWEEN 64 AND 74
),
med_complexity AS (
  SELECT 
    f.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM filtered_age f
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON f.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN f.admittime AND TIMESTAMP_ADD(f.admittime, INTERVAL 24 HOUR)
  GROUP BY f.hadm_id
),
readmissions_v2 AS (
  SELECT 
    a1.hadm_id,
    MAX(CASE WHEN a2.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS readmitted_30d
  FROM filtered_age a1
  LEFT JOIN filtered_age a2 
    ON a1.subject_id = a2.subject_id
    AND a2.admittime > a1.admittime
    AND a2.admittime <= TIMESTAMP_ADD(a1.dischtime, INTERVAL 30 DAY)
  GROUP BY a1.hadm_id
),
combined AS (
  SELECT 
    f.hadm_id,
    f.admittime,
    f.dischtime,
    f.hospital_expire_flag,
    f.age,
    f.gender,
    m.med_count,
    r.readmitted_30d,
    TIMESTAMP_DIFF(f.dischtime, f.admittime, DAY) AS los_days,
    NTILE(3) OVER (ORDER BY m.med_count) AS tertile
  FROM filtered_age f
  LEFT JOIN med_complexity m ON f.hadm_id = m.hadm_id
  LEFT JOIN readmissions_v2 r ON f.hadm_id = r.hadm_id
)
SELECT 
  tertile,
  COUNT(*) AS admissions,
  MIN(med_count) AS min_med_score,
  MAX(med_count) AS max_med_score,
  AVG(los_days) AS avg_los_days,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS mortality_pct,
  SUM(readmitted_30d) * 100.0 / COUNT(*) AS readmission_pct
FROM combined
GROUP BY tertile
ORDER BY tertile;