WITH patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 76 AND 86
),

cardiac_arrest AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%cardiac arrest%'
),

medication_complexity AS (
  SELECT
    ca.hadm_id,
    COUNT(DISTINCT pr.drug) AS med_count
  FROM cardiac_arrest ca
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ca.hadm_id = pr.hadm_id
    AND pr.starttime >= ca.admittime
    AND pr.starttime < DATETIME_ADD(ca.admittime, INTERVAL 7 DAY)
  GROUP BY ca.hadm_id
),

quintiles AS (
  SELECT
    ca.*,
    mc.med_count,
    NTILE(5) OVER (ORDER BY mc.med_count) AS quintile
  FROM cardiac_arrest ca
  JOIN medication_complexity mc ON ca.hadm_id = mc.hadm_id
),

readmissions AS (
  SELECT
    q.*,
    LEAD(q.admittime) OVER (PARTITION BY q.subject_id ORDER BY q.admittime) AS next_admittime
  FROM quintiles q
),

summary_stats AS (
  SELECT
    quintile,
    COUNT(*) AS patient_count,
    AVG(med_count) AS avg_score,
    MIN(med_count) AS min_score,
    MAX(med_count) AS max_score,
    AVG(DATETIME_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
    AVG(IF(hospital_expire_flag = 1, 1, 0)) AS in_hospital_mortality_rate,
    AVG(IF(
      next_admittime IS NOT NULL AND DATETIME_DIFF(next_admittime, dischtime, DAY) <= 30,
      1, 0
    )) AS thirty_day_readmission_rate
  FROM readmissions
  GROUP BY quintile
)

SELECT
  quintile,
  patient_count,
  ROUND(avg_score, 2) AS avg_score,
  min_score,
  max_score,
  ROUND(avg_los_days, 2) AS avg_los_days,
  ROUND(in_hospital_mortality_rate * 100, 2) AS in_hospital_mortality_percent,
  ROUND(thirty_day_readmission_rate * 100, 2) AS thirty_day_readmission_percent
FROM summary_stats
ORDER BY quintile;