WITH base_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 76 AND 86
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND d.icd_code LIKE 'I46%'
        AND d.icd_version = 10
    )
),
med_complexity AS (
  SELECT 
    b.hadm_id,
    COUNT(DISTINCT p.drug) AS med_count
  FROM base_admissions b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON p.hadm_id = b.hadm_id
    AND p.starttime < b.admittime + INTERVAL '7' DAY
    AND (p.stoptime > b.admittime OR p.stoptime IS NULL)
  GROUP BY b.hadm_id
),
readmission_flag AS (
  SELECT 
    b.hadm_id AS index_hadm_id,
    CASE WHEN COUNT(a2.hadm_id) > 0 THEN 1 ELSE 0 END AS readmitted_30d
  FROM base_admissions b
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2
    ON b.subject_id = a2.subject_id
    AND a2.admittime > b.dischtime
    AND a2.admittime <= b.dischtime + INTERVAL '30' DAY
    AND a2.hadm_id != b.hadm_id
  GROUP BY b.hadm_id
),
combined AS (
  SELECT 
    b.hadm_id,
    b.admittime,
    b.dischtime,
    b.hospital_expire_flag,
    COALESCE(m.med_count, 0) AS med_count,
    r.readmitted_30d,
    DATETIME_DIFF(b.dischtime, b.admittime, DAY) AS los_days
  FROM base_admissions b
  LEFT JOIN med_complexity m 
    ON b.hadm_id = m.hadm_id
  LEFT JOIN readmission_flag r 
    ON b.hadm_id = r.index_hadm_id
),
with_quintiles AS (
  SELECT 
    *,
    NTILE(5) OVER (ORDER BY med_count) AS quintile
  FROM combined
)
SELECT 
  quintile,
  COUNT(*) AS patient_count,
  AVG(med_count) AS avg_med_count,
  MIN(med_count) AS min_med_count,
  MAX(med_count) AS max_med_count,
  AVG(los_days) AS avg_los_days,
  (SUM(hospital_expire_flag) * 100.0 / COUNT(*)) AS mortality_pct,
  (SUM(readmitted_30d) * 100.0 / COUNT(*)) AS readmission_pct
FROM with_quintiles
GROUP BY quintile
ORDER BY quintile;