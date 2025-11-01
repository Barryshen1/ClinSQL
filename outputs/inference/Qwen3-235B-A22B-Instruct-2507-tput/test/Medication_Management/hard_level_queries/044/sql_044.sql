WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 64 AND 74
),

pe_admissions AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%pulmonary embolism%'
     OR (d.icd_code = 'I26.9' AND d.icd_version = 10)
     OR (d.icd_code = '415.1' AND d.icd_version = 9)
),

medication_counts AS (
  SELECT
    pa.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM pe_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions pr
    ON pa.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= pa.admittime
    AND pr.starttime <= DATETIME_ADD(pa.admittime, INTERVAL 24 HOUR)
  GROUP BY pa.hadm_id
),

tertile_groups AS (
  SELECT
    mc.hadm_id,
    mc.med_count,
    NTILE(3) OVER (ORDER BY mc.med_count) AS tertile
  FROM medication_counts mc
),

readmission_flags AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.hospital_expire_flag,
    DATETIME_DIFF(pa.dischtime, pa.admittime, HOUR) / 24.0 AS los_days,
    LEAD(pa.admittime) OVER (PARTITION BY pa.subject_id ORDER BY pa.admittime) AS next_admittime
  FROM pe_admissions pa
),

readmission_summary AS (
  SELECT
    rf.hadm_id,
    rf.los_days,
    rf.hospital_expire_flag,
    CASE
      WHEN rf.next_admittime IS NOT NULL AND DATETIME_DIFF(rf.next_admittime, rf.dischtime, DAY) <= 30
      THEN 1 ELSE 0
    END AS thirty_day_readmit
  FROM readmission_flags rf
)

SELECT
  tg.tertile,
  COUNT(*) AS admissions,
  MIN(tg.med_count) AS min_meds,
  MAX(tg.med_count) AS max_meds,
  ROUND(AVG(rs.los_days), 2) AS avg_los_days,
  ROUND(100.0 * AVG(CAST(rs.hospital_expire_flag AS FLOAT64)), 2) AS mortality_pct,
  ROUND(100.0 * AVG(CAST(rs.thirty_day_readmit AS FLOAT64)), 2) AS thirty_day_readmit_pct
FROM tertile_groups tg
INNER JOIN readmission_summary rs
  ON tg.hadm_id = rs.hadm_id
GROUP BY tg.tertile
ORDER BY tg.tertile;